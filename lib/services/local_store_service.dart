import 'package:hive_flutter/hive_flutter.dart';

import '../core/models/folder_item.dart';
import '../core/models/note_item.dart';
import '../core/models/sync_mutation.dart';
import '../core/models/template_item.dart';

class LocalStoreService {
  static const String notesBoxName = 'notes_box';
  static const String foldersBoxName = 'folders_box';
  static const String templatesBoxName = 'templates_box';
  static const String settingsBoxName = 'settings_box';
  static const String queueBoxName = 'sync_queue_box';
  static const String noteVersionsBoxName = 'note_versions_box';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    await Hive.initFlutter();
    await Future.wait(<Future<void>>[
      Hive.openBox<dynamic>(notesBoxName),
      Hive.openBox<dynamic>(foldersBoxName),
      Hive.openBox<dynamic>(templatesBoxName),
      Hive.openBox<dynamic>(settingsBoxName),
      Hive.openBox<dynamic>(queueBoxName),
      Hive.openBox<dynamic>(noteVersionsBoxName),
    ]);

    _initialized = true;
  }

  Box<dynamic> _box(String name) => Hive.box<dynamic>(name);

  List<NoteItem> readNotesForUser(String ownerId) {
    final Box<dynamic> box = _box(notesBoxName);
    return box.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> raw) => _toStringDynamicMap(raw))
        .where((Map<String, dynamic> map) => map['ownerId'] == ownerId)
        .map(NoteItem.fromMap)
        .toList(growable: false)
      ..sort((NoteItem a, NoteItem b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> upsertNote(NoteItem note) async {
    await _box(notesBoxName).put(note.id, note.toMap());
  }

  NoteItem? readNoteById(String noteId) {
    final dynamic raw = _box(notesBoxName).get(noteId);
    if (raw is! Map) {
      return null;
    }

    return NoteItem.fromMap(_toStringDynamicMap(raw));
  }

  Future<void> deleteNote(String noteId) async {
    await _box(notesBoxName).delete(noteId);
  }

  List<FolderItem> readFoldersForUser(String ownerId) {
    final Box<dynamic> box = _box(foldersBoxName);
    return box.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> raw) => _toStringDynamicMap(raw))
        .where((Map<String, dynamic> map) => map['ownerId'] == ownerId)
        .map(FolderItem.fromMap)
        .toList(growable: false)
      ..sort((FolderItem a, FolderItem b) => a.name.compareTo(b.name));
  }

  Future<void> upsertFolder(FolderItem folder) async {
    await _box(foldersBoxName).put(folder.id, folder.toMap());
  }

  Future<void> deleteFolder(String folderId) async {
    await _box(foldersBoxName).delete(folderId);
  }

  List<TemplateItem> readTemplatesForUser(String ownerId) {
    final Box<dynamic> box = _box(templatesBoxName);
    return box.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> raw) => _toStringDynamicMap(raw))
        .where(
          (Map<String, dynamic> map) =>
              map['isBuiltIn'] == true || map['ownerId'] == ownerId,
        )
        .map(TemplateItem.fromMap)
        .toList(growable: false);
  }

  Future<void> upsertTemplate(TemplateItem template) async {
    await _box(templatesBoxName).put(template.id, template.toMap());
  }

  Future<void> deleteTemplate(String templateId) async {
    await _box(templatesBoxName).delete(templateId);
  }

  /// Ids of built-in templates currently stored (any owner).
  List<String> readBuiltInTemplateIds() {
    return _box(templatesBoxName)
        .values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> raw) => _toStringDynamicMap(raw))
        .where((Map<String, dynamic> map) => map['isBuiltIn'] == true)
        .map((Map<String, dynamic> map) => map['id'].toString())
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Generic preferences
  // ---------------------------------------------------------------------------

  T? readSetting<T>(String key) {
    final dynamic value = _box(settingsBoxName).get(key);
    return value is T ? value : null;
  }

  Future<void> saveSetting(String key, Object? value) async {
    await _box(settingsBoxName).put(key, value);
  }

  Set<String> readStringSet(String key) {
    final dynamic value = _box(settingsBoxName).get(key);
    if (value is! List) {
      return <String>{};
    }
    return value.map((dynamic e) => e.toString()).toSet();
  }

  Future<void> saveStringSet(String key, Set<String> values) async {
    await _box(settingsBoxName).put(key, values.toList(growable: false));
  }

  Future<void> enqueueMutation(SyncMutation mutation) async {
    await _box(queueBoxName).put(mutation.id, mutation.toMap());
  }

  List<SyncMutation> readQueue() {
    final Box<dynamic> box = _box(queueBoxName);
    return box.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> raw) => _toStringDynamicMap(raw))
        .map(SyncMutation.fromMap)
        .toList(growable: false)
      ..sort((SyncMutation a, SyncMutation b) =>
          a.createdAt.compareTo(b.createdAt));
  }

  Future<void> removeMutation(String mutationId) async {
    await _box(queueBoxName).delete(mutationId);
  }

  String? readSelectedThemeId() {
    return _box(settingsBoxName).get('selected_theme_id') as String?;
  }

  Future<void> saveSelectedThemeId(String themeId) async {
    await _box(settingsBoxName).put('selected_theme_id', themeId);
  }

  String? readThemeMode() {
    return _box(settingsBoxName).get('theme_mode') as String?;
  }

  Future<void> saveThemeMode(String mode) async {
    await _box(settingsBoxName).put('theme_mode', mode);
  }

  bool readStaySignedIn() {
    return _box(settingsBoxName).get('stay_signed_in') as bool? ?? true;
  }

  Future<void> saveStaySignedIn(bool value) async {
    await _box(settingsBoxName).put('stay_signed_in', value);
  }

  bool readOfflineAccessGranted() {
    return _box(settingsBoxName).get('offline_access_granted') as bool? ??
        false;
  }

  Future<void> saveOfflineAccessGranted(bool value) async {
    await _box(settingsBoxName).put('offline_access_granted', value);
  }

  Set<String> readLockedFolderIds() {
    final List<dynamic> ids =
        _box(settingsBoxName).get('locked_folder_ids') as List<dynamic>? ??
            const <dynamic>[];
    return ids.map((dynamic id) => id.toString()).toSet();
  }

  Future<void> saveLockedFolderIds(Set<String> ids) async {
    await _box(settingsBoxName).put('locked_folder_ids', ids.toList());
  }

  Future<void> appendNoteVersion(NoteItem note) async {
    final Box<dynamic> box = _box(noteVersionsBoxName);
    final List<dynamic> existing =
        box.get(note.id) as List<dynamic>? ?? <dynamic>[];

    final List<Map<String, dynamic>> history = existing
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => _toStringDynamicMap(item))
        .toList(growable: true);

    // Autosave fires every second while typing. Keep one snapshot per burst of
    // editing (a new one after 3 quiet minutes) instead of one per keystroke.
    if (history.isNotEmpty) {
      final DateTime? lastAt =
          DateTime.tryParse(history.last['updatedAt']?.toString() ?? '');
      if (lastAt != null &&
          note.updatedAt.difference(lastAt).abs() < const Duration(minutes: 3)) {
        history.removeLast();
      }
    }
    history.add(note.toMap());
    if (history.length > 40) {
      history.removeRange(0, history.length - 40);
    }

    await box.put(note.id, history);
  }

  List<NoteItem> readNoteVersions(String noteId) {
    final List<dynamic> existing =
        _box(noteVersionsBoxName).get(noteId) as List<dynamic>? ?? <dynamic>[];

    final List<NoteItem> versions = existing
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => _toStringDynamicMap(item))
        .map(NoteItem.fromMap)
        .toList(growable: false);

    return versions.reversed.toList(growable: false);
  }

  Future<void> clearNoteVersions(String noteId) async {
    await _box(noteVersionsBoxName).delete(noteId);
  }

  Future<void> clearUserData(String ownerId) async {
    final List<NoteItem> notes = readNotesForUser(ownerId);
    final List<FolderItem> folders = readFoldersForUser(ownerId);

    for (final NoteItem note in notes) {
      await deleteNote(note.id);
      await clearNoteVersions(note.id);
    }
    for (final FolderItem folder in folders) {
      await deleteFolder(folder.id);
    }
  }

  Map<String, dynamic> _toStringDynamicMap(Map<dynamic, dynamic> raw) {
    return raw.map(
      (dynamic key, dynamic value) => MapEntry(key.toString(), value),
    );
  }
}
