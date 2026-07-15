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
/// Conflict handling mirrors the original design: if the remote revision is
/// newer than the local one, keep both copies (the remote wins the canonical
/// id, the local edit becomes a "Conflict Copy").
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
    final List<SyncMutation> queue = _localStore.readQueue();

    for (final SyncMutation mutation in queue) {
      try {
        switch (mutation.operation) {
          case SyncOperation.upsertNote:
            await _syncNoteUpsert(
              client: client,
              userId: userId,
              mutation: mutation,
            );
            break;
          case SyncOperation.deleteNote:
            await client
                .from(_notesTable)
                .delete()
                .eq('id', mutation.entityId)
                .eq('owner_id', userId);
            break;
          case SyncOperation.upsertFolder:
            await client.from(_foldersTable).upsert(<String, dynamic>{
              'id': mutation.entityId,
              'owner_id': userId,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
              'data': mutation.payload,
            });
            break;
          case SyncOperation.deleteFolder:
            await client
                .from(_foldersTable)
                .delete()
                .eq('id', mutation.entityId)
                .eq('owner_id', userId);
            break;
        }

        await _localStore.removeMutation(mutation.id);
      } catch (_) {
        // Stop on the first failure; the queue is retried on the next tick.
        return false;
      }
    }

    return true;
  }

  Future<void> _syncNoteUpsert({
    required SupabaseClient client,
    required String userId,
    required SyncMutation mutation,
  }) async {
    final Map<String, dynamic> localMap = mutation.payload;
    final int localRevision = localMap['revision'] as int? ?? 0;

    final Map<String, dynamic>? remoteRow = await client
        .from(_notesTable)
        .select('revision, data')
        .eq('id', mutation.entityId)
        .maybeSingle();

    if (remoteRow != null) {
      final int remoteRevision = remoteRow['revision'] as int? ?? 0;
      if (remoteRevision > localRevision) {
        final Map<String, dynamic> remoteData =
            Map<String, dynamic>.from(remoteRow['data'] as Map<dynamic, dynamic>);
        await _resolveConflictKeepBoth(
          remote: remoteData,
          localMap: localMap,
        );
        return;
      }
    }

    final int newRevision = localRevision + 1;
    final Map<String, dynamic> uploadMap = <String, dynamic>{
      ...localMap,
      'localOnly': false,
      'revision': newRevision,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    await client.from(_notesTable).upsert(<String, dynamic>{
      'id': mutation.entityId,
      'owner_id': userId,
      'revision': newRevision,
      'updated_at': uploadMap['updatedAt'],
      'data': uploadMap,
    });

    await _localStore.upsertNote(NoteItem.fromMap(uploadMap));
  }

  Future<void> _resolveConflictKeepBoth({
    required Map<String, dynamic> remote,
    required Map<String, dynamic> localMap,
  }) async {
    final NoteItem local = NoteItem.fromMap(localMap);
    final NoteItem remoteNote = NoteItem.fromMap(remote);
    final String conflictId = _uuid.v4();

    final NoteItem conflictCopy = local.copyWith(
      id: conflictId,
      title: '${local.title} (Conflict Copy)',
      conflictGroupId: local.id,
      localOnly: true,
      revision: 0,
      updatedAt: DateTime.now().toUtc(),
    );

    await _localStore.upsertNote(remoteNote.copyWith(localOnly: false));
    await _localStore.upsertNote(conflictCopy);
    await queueNoteUpsert(conflictCopy);

    await _localStore.enqueueMutation(
      SyncMutation(
        id: _uuid.v4(),
        operation: SyncOperation.upsertNote,
        entityId: local.id,
        payload: remoteNote.toMap(),
        createdAt: DateTime.now().toUtc(),
      ),
    );
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
