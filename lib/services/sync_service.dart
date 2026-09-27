import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/models/folder_item.dart';
import '../core/models/note_item.dart';
import '../core/models/sync_mutation.dart';
import 'auth_service.dart';
import 'local_store_service.dart';
import 'sync_planner.dart';

/// What a pull changed locally, so the controller can react (refresh the UI,
/// reschedule reminders for notes edited on another device, and so on).
class PullOutcome {
  const PullOutcome({
    this.changedNotes = const <NoteItem>[],
    this.deletedNoteIds = const <String>[],
    this.changedFolderCount = 0,
    this.deletedFolderCount = 0,
  });

  final List<NoteItem> changedNotes;
  final List<String> deletedNoteIds;
  final int changedFolderCount;
  final int deletedFolderCount;

  bool get hasChanges =>
      changedNotes.isNotEmpty ||
      deletedNoteIds.isNotEmpty ||
      changedFolderCount > 0 ||
      deletedFolderCount > 0;
}

/// Two-way sync between the local Hive store and Supabase.
///
/// Notes and folders are stored as rows of the form
/// `{ id, owner_id, revision, updated_at, data: <jsonb> }`, where `data` holds
/// the same map the app persists locally, so the on-device and cloud formats
/// are identical.
///
/// * **Push** drains the local mutation queue (collapsed to the latest edit per
///   entity). Conflicts are last-write-wins.
/// * **Pull** compares cheap cloud metadata (`id, updated_at`) with the local
///   store and downloads only what changed. See [SyncPlanner] for the rules.
/// * **Realtime** listens for row changes from other devices and asks the
///   controller to pull, so edits appear within a second or two.
class SyncService {
  SyncService({
    required LocalStoreService localStore,
    required AuthService authService,
  })  : _localStore = localStore,
        _authService = authService;

  final LocalStoreService _localStore;
  final AuthService _authService;
  final Uuid _uuid = const Uuid();
  final Connectivity _connectivity = Connectivity();

  static const String _notesTable = 'notes';
  static const String _foldersTable = 'folders';
  static const int _pageSize = 1000;
  static const int _fetchChunk = 50;

  RealtimeChannel? _channel;
  bool _realtimeConnected = false;

  bool get realtimeConnected => _realtimeConnected;

  bool get _cloudActive =>
      _authService.isCloudReady && _authService.isSignedIn;

  // ---------------------------------------------------------------------------
  // Queue
  // ---------------------------------------------------------------------------

  Future<void> queueNoteUpsert(NoteItem note) =>
      _enqueue(SyncOperation.upsertNote, note.id, note.toMap());

  Future<void> queueNoteDelete(String noteId) => _enqueue(
      SyncOperation.deleteNote, noteId, <String, dynamic>{'noteId': noteId});

  Future<void> queueFolderUpsert(FolderItem folder) =>
      _enqueue(SyncOperation.upsertFolder, folder.id, folder.toMap());

  Future<void> queueFolderDelete(String folderId) => _enqueue(
        SyncOperation.deleteFolder,
        folderId,
        <String, dynamic>{'folderId': folderId},
      );

  Future<void> _enqueue(
    SyncOperation operation,
    String entityId,
    Map<String, dynamic> payload,
  ) {
    return _localStore.enqueueMutation(
      SyncMutation(
        id: _uuid.v4(),
        operation: operation,
        entityId: entityId,
        payload: payload,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Number of entities with changes waiting to upload.
  int get pendingCount => _pendingKeys().length;

  Set<String> _pendingKeys() => _localStore
      .readQueue()
      .map((SyncMutation m) => _key(m.operation, m.entityId))
      .toSet();

  Set<String> _pendingIds(String kind) => _localStore
      .readQueue()
      .where((SyncMutation m) => _entityKind(m.operation) == kind)
      .map((SyncMutation m) => m.entityId)
      .toSet();

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  /// Uploads queued edits. Returns false if offline, signed out, or a request
  /// failed (the remaining queue is retried on the next cycle).
  Future<bool> pushPending() async {
    if (!_cloudActive || !await hasConnection()) {
      return false;
    }

    final SupabaseClient client = Supabase.instance.client;
    final String userId = _authService.currentUserId;

    // Collapse the queue: for each entity keep only its most recent operation,
    // and remember every mutation id for that entity so all of them can be
    // cleared once the latest has been applied.
    final List<SyncMutation> raw = _localStore.readQueue();
    final Map<String, SyncMutation> latest = <String, SyncMutation>{};
    final Map<String, List<String>> ids = <String, List<String>>{};
    for (final SyncMutation m in raw) {
      final String key = _key(m.operation, m.entityId);
      latest[key] = m; // raw is createdAt-ascending, so the last one wins
      (ids[key] ??= <String>[]).add(m.id);
    }

    final List<SyncMutation> collapsed = latest.values.toList()
      ..sort((SyncMutation a, SyncMutation b) =>
          a.createdAt.compareTo(b.createdAt));

    for (final SyncMutation mutation in collapsed) {
      final String key = _key(mutation.operation, mutation.entityId);
      try {
        Map<String, dynamic>? pushed;
        switch (mutation.operation) {
          case SyncOperation.upsertNote:
            pushed = await _upsert(client, _notesTable, userId, mutation);
            break;
          case SyncOperation.upsertFolder:
            pushed = await _upsert(client, _foldersTable, userId, mutation);
            break;
          case SyncOperation.deleteNote:
            await client
                .from(_notesTable)
                .delete()
                .eq('id', mutation.entityId)
                .eq('owner_id', userId);
            break;
          case SyncOperation.deleteFolder:
            await client
                .from(_foldersTable)
                .delete()
                .eq('id', mutation.entityId)
                .eq('owner_id', userId);
            break;
        }

        for (final String id in ids[key] ?? const <String>[]) {
          await _localStore.removeMutation(id);
        }

        // Record the synced state locally, but only if nothing newer was typed
        // while the request was in flight. A newer edit has its own queued
        // mutation; overwriting the local copy here would briefly revert it.
        if (pushed != null && !_pendingKeys().contains(key)) {
          if (mutation.operation == SyncOperation.upsertNote) {
            await _localStore.upsertNote(NoteItem.fromMap(pushed));
          } else {
            await _localStore.upsertFolder(FolderItem.fromMap(pushed));
          }
        }
      } catch (_) {
        return false; // stop at the first failure; retried next cycle
      }
    }

    return true;
  }

  /// Last-write-wins upsert. Returns the map that was stored in the cloud.
  Future<Map<String, dynamic>> _upsert(
    SupabaseClient client,
    String table,
    String userId,
    SyncMutation mutation,
  ) async {
    final Map<String, dynamic> localMap = mutation.payload;
    final int revision = (localMap['revision'] as int? ?? 0) + 1;
    final String now = DateTime.now().toUtc().toIso8601String();

    final Map<String, dynamic> uploadMap = <String, dynamic>{
      ...localMap,
      'localOnly': false,
      'revision': revision,
      'updatedAt': now,
    };

    final Map<String, dynamic> row = <String, dynamic>{
      'id': mutation.entityId,
      'owner_id': userId,
      'updated_at': now,
      'data': uploadMap,
    };
    if (table == _notesTable) {
      row['revision'] = revision; // folders have no revision column
    }

    await client.from(table).upsert(row);
    return uploadMap;
  }

  // ---------------------------------------------------------------------------
  // Pull
  // ---------------------------------------------------------------------------

  /// Downloads changes made on other devices. Returns null if the pull could
  /// not run (offline, signed out, or a request failed).
  Future<PullOutcome?> pull() async {
    if (!_cloudActive || !await hasConnection()) {
      return null;
    }

    final SupabaseClient client = Supabase.instance.client;
    final String userId = _authService.currentUserId;

    try {
      // ---- folders first, so notes never land in a folder we lack ----------
      final Map<String, DateTime> remoteFolders =
          await _remoteMeta(client, _foldersTable, userId);
      final List<FolderItem> localFolderList =
          _localStore.readFoldersForUser(userId);
      final SyncPlan folderPlan = SyncPlanner.plan(
        local: <String, LocalEntityState>{
          for (final FolderItem f in localFolderList)
            f.id: LocalEntityState(
              updatedAt: f.updatedAt,
              // Folders have no localOnly flag; a folder is "synced" once it
              // has no pending mutation, which the planner checks separately.
              synced: true,
            ),
        },
        remote: remoteFolders,
        pending: _pendingIds('folder'),
      );

      final List<Map<String, dynamic>> folderRows =
          await _fetchData(client, _foldersTable, folderPlan.fetch);
      for (final Map<String, dynamic> data in folderRows) {
        await _localStore.upsertFolder(FolderItem.fromMap(data));
      }
      for (final String id in folderPlan.deleteLocal) {
        await _localStore.deleteFolder(id);
      }

      // ---- notes -------------------------------------------------------------
      final Map<String, DateTime> remoteNotes =
          await _remoteMeta(client, _notesTable, userId);
      final List<NoteItem> localNoteList = _localStore.readNotesForUser(userId);
      final Map<String, NoteItem> localNotes = <String, NoteItem>{
        for (final NoteItem n in localNoteList) n.id: n,
      };
      final SyncPlan notePlan = SyncPlanner.plan(
        local: <String, LocalEntityState>{
          for (final NoteItem n in localNoteList)
            n.id: LocalEntityState(updatedAt: n.updatedAt, synced: !n.localOnly),
        },
        remote: remoteNotes,
        pending: _pendingIds('note'),
      );

      final List<NoteItem> changed = <NoteItem>[];
      final List<Map<String, dynamic>> noteRows =
          await _fetchData(client, _notesTable, notePlan.fetch);
      for (final Map<String, dynamic> data in noteRows) {
        final NoteItem note =
            NoteItem.fromMap(data).copyWith(localOnly: false);
        await _localStore.upsertNote(note);
        changed.add(note);
      }
      for (final String id in notePlan.deleteLocal) {
        await _localStore.deleteNote(id);
        await _localStore.clearNoteVersions(id);
      }
      for (final String id in notePlan.reupload) {
        final NoteItem? orphan = localNotes[id];
        if (orphan != null) {
          await queueNoteUpsert(orphan);
        }
      }

      return PullOutcome(
        changedNotes: changed,
        deletedNoteIds: notePlan.deleteLocal,
        changedFolderCount: folderRows.length,
        deletedFolderCount: folderPlan.deleteLocal.length,
      );
    } catch (_) {
      return null;
    }
  }

  /// `id -> updated_at` for every row the user owns, paginated so accounts with
  /// more than one page of rows are never mistaken for deletions.
  Future<Map<String, DateTime>> _remoteMeta(
    SupabaseClient client,
    String table,
    String userId,
  ) async {
    final Map<String, DateTime> meta = <String, DateTime>{};
    int from = 0;
    while (true) {
      final List<Map<String, dynamic>> page = await client
          .from(table)
          .select('id, updated_at')
          .eq('owner_id', userId)
          .order('id')
          .range(from, from + _pageSize - 1);
      for (final Map<String, dynamic> row in page) {
        meta[row['id'] as String] =
            DateTime.parse(row['updated_at'] as String).toUtc();
      }
      if (page.length < _pageSize) {
        break;
      }
      from += _pageSize;
    }
    return meta;
  }

  /// Downloads the `data` payload for [ids], in small batches to keep request
  /// URLs short.
  Future<List<Map<String, dynamic>>> _fetchData(
    SupabaseClient client,
    String table,
    List<String> ids,
  ) async {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (int i = 0; i < ids.length; i += _fetchChunk) {
      final List<String> chunk =
          ids.sublist(i, (i + _fetchChunk).clamp(0, ids.length));
      final List<Map<String, dynamic>> rows =
          await client.from(table).select('id, data').inFilter('id', chunk);
      for (final Map<String, dynamic> row in rows) {
        final Object? data = row['data'];
        if (data is Map) {
          out.add(Map<String, dynamic>.from(data));
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Realtime
  // ---------------------------------------------------------------------------

  /// Subscribes to changes on the user's rows. [onRemoteChange] fires for every
  /// insert/update (including this device's own pushes, which then pull as a
  /// cheap no-op). Deletes are picked up by the periodic pull instead, because
  /// Realtime cannot filter DELETE events by owner.
  void startRealtime(void Function() onRemoteChange) {
    if (!_cloudActive || _channel != null) {
      return;
    }
    final SupabaseClient client = Supabase.instance.client;
    final String userId = _authService.currentUserId;
    final PostgresChangeFilter ownerFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'owner_id',
      value: userId,
    );

    _channel = client
        .channel('notebook-sync-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _notesTable,
          filter: ownerFilter,
          callback: (_) => onRemoteChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _foldersTable,
          filter: ownerFilter,
          callback: (_) => onRemoteChange(),
        )
        .subscribe((RealtimeSubscribeStatus status, Object? error) {
      _realtimeConnected = status == RealtimeSubscribeStatus.subscribed;
    });
  }

  Future<void> stopRealtime() async {
    final RealtimeChannel? channel = _channel;
    _channel = null;
    _realtimeConnected = false;
    if (channel != null) {
      try {
        await Supabase.instance.client.removeChannel(channel);
      } catch (_) {
        // Channel already closed; nothing to do.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _key(SyncOperation op, String entityId) =>
      '${_entityKind(op)}:$entityId';

  String _entityKind(SyncOperation op) {
    switch (op) {
      case SyncOperation.upsertNote:
      case SyncOperation.deleteNote:
        return 'note';
      case SyncOperation.upsertFolder:
      case SyncOperation.deleteFolder:
        return 'folder';
    }
  }

  Future<bool> hasConnection() async {
    final dynamic result = await _connectivity.checkConnectivity();
    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }
    if (result is List<ConnectivityResult>) {
      return !result.contains(ConnectivityResult.none);
    }
    return true;
  }
}
