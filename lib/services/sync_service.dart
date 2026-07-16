import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/models/folder_item.dart';
import '../core/models/note_item.dart';
import '../core/models/sync_mutation.dart';
import 'auth_service.dart';
import 'local_store_service.dart';

/// Pushes the local mutation queue to Supabase.
///
/// Notes and folders are stored as rows of the form
/// `{ id, owner_id, revision, updated_at, data: <jsonb> }`, where `data` holds
/// the same map the app persists locally. This keeps the on-device format and
/// the cloud format identical, so no field-by-field mapping is required.
///
/// Sync strategy is last-write-wins: the most recent push for a given id wins.
/// A device's own sequential edits are never treated as conflicts (that would
/// duplicate a note every time an autosave lands after the cloud advanced).
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

  Future<void> queueNoteUpsert(NoteItem note) {
    return _localStore.enqueueMutation(
      SyncMutation(
        id: _uuid.v4(),
        operation: SyncOperation.upsertNote,
        entityId: note.id,
        payload: note.toMap(),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> queueNoteDelete(String noteId) {
    return _localStore.enqueueMutation(
      SyncMutation(
        id: _uuid.v4(),
        operation: SyncOperation.deleteNote,
        entityId: noteId,
        payload: <String, dynamic>{'noteId': noteId},
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> queueFolderUpsert(FolderItem folder) {
    return _localStore.enqueueMutation(
      SyncMutation(
        id: _uuid.v4(),
        operation: SyncOperation.upsertFolder,
        entityId: folder.id,
        payload: folder.toMap(),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> queueFolderDelete(String folderId) {
    return _localStore.enqueueMutation(
      SyncMutation(
        id: _uuid.v4(),
        operation: SyncOperation.deleteFolder,
        entityId: folderId,
        payload: <String, dynamic>{'folderId': folderId},
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<bool> syncPendingMutations() async {
    if (!_authService.isCloudReady || !_authService.isSignedIn) {
      return false;
    }

    if (!await _hasConnection()) {
      return false;
    }

    final SupabaseClient client = Supabase.instance.client;
    final String userId = _authService.currentUserId;

    // Collapse the queue: for each entity keep only its most recent operation,
    // and track every queued mutation id for that entity so all of them are
    // cleared once the latest is applied. This prevents a backlog of stale
    // autosaves from each hitting the network (and, previously, self-conflicting).
    final List<SyncMutation> raw = _localStore.readQueue();
    final Map<String, SyncMutation> latest = <String, SyncMutation>{};
    final Map<String, List<String>> ids = <String, List<String>>{};
    for (final SyncMutation m in raw) {
      final String key = '${_entityKind(m.operation)}:${m.entityId}';
      latest[key] = m; // raw is createdAt-ascending, so the last wins
      (ids[key] ??= <String>[]).add(m.id);
    }

    final List<SyncMutation> collapsed = latest.values.toList()
      ..sort((SyncMutation a, SyncMutation b) =>
          a.createdAt.compareTo(b.createdAt));

    for (final SyncMutation mutation in collapsed) {
      final String key = '${_entityKind(mutation.operation)}:${mutation.entityId}';
      try {
        switch (mutation.operation) {
          case SyncOperation.upsertNote:
            await _upsert(client, _notesTable, userId, mutation);
            break;
          case SyncOperation.deleteNote:
            await client
                .from(_notesTable)
                .delete()
                .eq('id', mutation.entityId)
                .eq('owner_id', userId);
            break;
          case SyncOperation.upsertFolder:
            await _upsert(client, _foldersTable, userId, mutation);
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
      } catch (_) {
        // Stop on the first failure; the queue is retried on the next tick.
        return false;
      }
    }

    return true;
  }

  /// Last-write-wins upsert. No remote read, no conflict path.
  Future<void> _upsert(
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

    await client.from(table).upsert(<String, dynamic>{
      'id': mutation.entityId,
      'owner_id': userId,
      'revision': revision,
      'updated_at': now,
      'data': uploadMap,
    });

    if (table == _notesTable) {
      await _localStore.upsertNote(NoteItem.fromMap(uploadMap));
    } else {
      await _localStore.upsertFolder(FolderItem.fromMap(uploadMap));
    }
  }

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

  Future<bool> _hasConnection() async {
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
