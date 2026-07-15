import 'package:flutter_test/flutter_test.dart';
import 'package:universal_notebook/core/models/folder_item.dart';
import 'package:universal_notebook/core/models/note_item.dart';

void main() {
  group('NoteItem serialization', () {
    test('round-trips through toMap/fromMap without loss', () {
      final DateTime now = DateTime.utc(2026, 7, 16, 10, 30);
      final NoteItem note = NoteItem(
        id: 'note-1',
        ownerId: 'owner-1',
        folderId: 'folder-1',
        title: 'Groceries',
        body: 'Milk\nEggs',
        createdAt: now,
        updatedAt: now,
        imagePaths: const <String>['a.png', 'b.png'],
        tags: const <String>['home', 'urgent'],
        localOnly: true,
        revision: 3,
        isPinned: true,
      );

      final NoteItem restored = NoteItem.fromMap(note.toMap());

      expect(restored.id, note.id);
      expect(restored.ownerId, note.ownerId);
      expect(restored.folderId, note.folderId);
      expect(restored.title, note.title);
      expect(restored.body, note.body);
      expect(restored.imagePaths, note.imagePaths);
      expect(restored.tags, note.tags);
      expect(restored.revision, note.revision);
      expect(restored.isPinned, isTrue);
      expect(restored.createdAt, now);
    });

    test('copyWith can clear the reminder and deletedAt fields', () {
      final DateTime now = DateTime.utc(2026, 7, 16);
      final NoteItem note = NoteItem(
        id: 'n',
        ownerId: 'o',
        folderId: 'f',
        title: 't',
        body: 'b',
        createdAt: now,
        updatedAt: now,
        imagePaths: const <String>[],
        tags: const <String>[],
        localOnly: true,
        revision: 0,
        reminderAt: now,
        deletedAt: now,
      );

      final NoteItem cleared =
          note.copyWith(clearReminder: true, clearDeletedAt: true);

      expect(cleared.reminderAt, isNull);
      expect(cleared.deletedAt, isNull);
    });
  });

  group('FolderItem serialization', () {
    test('round-trips through toMap/fromMap', () {
      final DateTime now = DateTime.utc(2026, 7, 16);
      final FolderItem folder = FolderItem(
        id: 'folder-1',
        ownerId: 'owner-1',
        name: 'Work',
        parentId: 'root',
        createdAt: now,
        updatedAt: now,
      );

      final FolderItem restored = FolderItem.fromMap(folder.toMap());

      expect(restored.id, folder.id);
      expect(restored.name, 'Work');
      expect(restored.parentId, 'root');
      expect(restored.ownerId, 'owner-1');
    });
  });
}
