import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/folder_item.dart';
import '../../core/models/note_item.dart';
import '../../state/notebook_controller.dart';
import 'note_editor_screen.dart';

class NotesDashboard extends StatelessWidget {
  const NotesDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth > 980;

        if (wide) {
          return Row(
            children: <Widget>[
              SizedBox(
                width: 320,
                child: _FolderPanel(controller: controller),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _NotesPanel(controller: controller),
              ),
            ],
          );
        }

        return Column(
          children: <Widget>[
            _CompactFolderSelector(controller: controller),
            const Divider(height: 1),
            Expanded(
              child: _NotesPanel(controller: controller),
            ),
          ],
        );
      },
    );
  }
}

class _CompactFolderSelector extends StatelessWidget {
  const _CompactFolderSelector({required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: controller.selectedFolderId,
              decoration: const InputDecoration(labelText: 'Folder'),
              items: controller.folders
                  .map(
                    (FolderItem folder) => DropdownMenuItem<String?>(
                      value: folder.id,
                      child: Text(folder.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (String? value) {
                controller.selectFolder(value);
              },
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'New folder',
            onPressed: () => _showCreateFolderDialog(context, controller),
            icon: const Icon(Icons.create_new_folder),
          ),
        ],
      ),
    );
  }
}

class _FolderPanel extends StatelessWidget {
  const _FolderPanel({required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    final Map<String?, List<FolderItem>> tree = <String?, List<FolderItem>>{};

    for (final FolderItem folder in controller.folders) {
      tree.putIfAbsent(folder.parentId, () => <FolderItem>[]).add(folder);
    }

    for (final List<FolderItem> level in tree.values) {
      level.sort((FolderItem a, FolderItem b) => a.name.compareTo(b.name));
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              title: const Text('Folders'),
              trailing: IconButton(
                tooltip: 'New folder',
                onPressed: () => _showCreateFolderDialog(context, controller),
                icon: const Icon(Icons.create_new_folder),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _buildFolderTiles(
                  context: context,
                  controller: controller,
                  tree: tree,
                  parentId: null,
                  depth: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFolderTiles({
    required BuildContext context,
    required NotebookController controller,
    required Map<String?, List<FolderItem>> tree,
    required String? parentId,
    required int depth,
  }) {
    final List<FolderItem> children = tree[parentId] ?? const <FolderItem>[];
    final List<Widget> widgets = <Widget>[];

    for (final FolderItem folder in children) {
      final bool isSelected = controller.selectedFolderId == folder.id;
      final bool isLocked = controller.isFolderLocked(folder.id);

      widgets.add(
        ListTile(
          dense: true,
          contentPadding:
              EdgeInsets.only(left: 8 + (depth * 18).toDouble(), right: 8),
          selected: isSelected,
          leading: Icon(isLocked ? Icons.lock : Icons.folder),
          title: Text(folder.name),
          trailing: Wrap(
            spacing: 2,
            children: <Widget>[
              IconButton(
                icon: Icon(isLocked ? Icons.lock_open : Icons.lock_outline),
                tooltip: isLocked ? 'Unlock folder setting' : 'Lock folder',
                onPressed: () => controller.toggleFolderLock(folder.id),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete folder',
                onPressed: () => controller.deleteFolder(folder.id),
              ),
            ],
          ),
          onTap: () => controller.selectFolder(folder.id),
        ),
      );

      widgets.addAll(
        _buildFolderTiles(
          context: context,
          controller: controller,
          tree: tree,
          parentId: folder.id,
          depth: depth + 1,
        ),
      );
    }

    return widgets;
  }
}

class _NotesPanel extends StatelessWidget {
  const _NotesPanel({required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    final List<NoteItem> notes = controller.filteredNotes;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!controller.cloudConfigured)
              MaterialBanner(
                content: const Text(
                  'Cloud sync is unavailable for this build. Notes are saved locally on this device.',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed:
                        controller.isBusy ? null : controller.retryCloudSetup,
                    child: const Text('Retry Setup'),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search notes',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: controller.setSearchQuery,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilterChip(
                        label: const Text('Show archived'),
                        selected: controller.showArchived,
                        onSelected: controller.setShowArchived,
                      ),
                      FilterChip(
                        label: const Text('Has images'),
                        selected: controller.hasImageFilter,
                        onSelected: controller.setHasImageFilter,
                      ),
                      ActionChip(
                        label: Text(
                          controller.filterStartDate == null &&
                                  controller.filterEndDate == null
                              ? 'Filter by date'
                              : 'Date filter active',
                        ),
                        onPressed: () => _showDateFilter(context, controller),
                      ),
                      ActionChip(
                        label: Text('Trash (${controller.trashNotes.length})'),
                        onPressed: () => _showTrashDialog(context, controller),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: notes.isEmpty
                  ? const Center(
                      child: Text('No notes yet. Create one to begin.'),
                    )
                  : ListView.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final NoteItem note = notes[index];
                        final String updated = DateFormat(
                          'EEE, d MMM y HH:mm',
                        ).format(note.updatedAt.toLocal());

                        return ListTile(
                          title: Text(note.title),
                          subtitle: Text(
                            '${note.body.replaceAll('\n', ' ')}\n$updated',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          leading: note.conflictGroupId == null
                              ? const Icon(Icons.note_outlined)
                              : const Icon(Icons.warning_amber_rounded),
                          trailing: PopupMenuButton<String>(
                            onSelected: (String value) async {
                              switch (value) {
                                case 'share':
                                  await controller.shareNote(note);
                                  break;
                                case 'pin':
                                  await controller.togglePin(note);
                                  break;
                                case 'archive':
                                  if (note.isArchived) {
                                    await controller.unarchiveNote(note);
                                  } else {
                                    await controller.archiveNote(note);
                                  }
                                  break;
                                case 'trash':
                                  await controller.moveToTrash(note);
                                  break;
                                default:
                                  break;
                              }
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<String>>[
                              const PopupMenuItem<String>(
                                value: 'share',
                                child: Text('Share'),
                              ),
                              PopupMenuItem<String>(
                                value: 'pin',
                                child: Text(note.isPinned ? 'Unpin' : 'Pin'),
                              ),
                              PopupMenuItem<String>(
                                value: 'archive',
                                child: Text(
                                    note.isArchived ? 'Unarchive' : 'Archive'),
                              ),
                              const PopupMenuItem<String>(
                                value: 'trash',
                                child: Text('Move to trash'),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    NoteEditorScreen(noteId: note.id),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showDateFilter(
  BuildContext context,
  NotebookController controller,
) async {
  final DateTime now = DateTime.now();

  final DateTime? startDate = await showDatePicker(
    context: context,
    initialDate: controller.filterStartDate ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 5),
  );

  if (startDate == null || !context.mounted) {
    return;
  }

  final DateTime? endDate = await showDatePicker(
    context: context,
    initialDate: controller.filterEndDate ?? startDate,
    firstDate: startDate,
    lastDate: DateTime(now.year + 5),
  );

  if (endDate == null) {
    return;
  }

  controller.setDateFilter(startDate: startDate, endDate: endDate);
}

Future<void> _showTrashDialog(
  BuildContext context,
  NotebookController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Trash'),
        content: SizedBox(
          width: 640,
          child: controller.trashNotes.isEmpty
              ? const Center(child: Text('Trash is empty.'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: controller.trashNotes.length,
                  itemBuilder: (BuildContext context, int index) {
                    final NoteItem note = controller.trashNotes[index];
                    return ListTile(
                      title: Text(note.title),
                      subtitle: Text(
                        note.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: <Widget>[
                          TextButton(
                            onPressed: () => controller.restoreFromTrash(note),
                            child: const Text('Restore'),
                          ),
                          TextButton(
                            onPressed: () =>
                                controller.permanentlyDeleteNote(note.id),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              controller.setDateFilter(startDate: null, endDate: null);
              controller.setHasImageFilter(false);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Clear Filters'),
          ),
        ],
      );
    },
  );
}

Future<void> _showCreateFolderDialog(
  BuildContext context,
  NotebookController controller,
) async {
  final TextEditingController nameController = TextEditingController();
  String? parentId = controller.selectedFolderId;

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Create Folder'),
        content: StatefulBuilder(
          builder: (
            BuildContext context,
            void Function(void Function()) setState,
          ) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Folder name'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: parentId,
                  decoration: const InputDecoration(labelText: 'Parent folder'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Top level'),
                    ),
                    ...controller.folders.map(
                      (FolderItem folder) => DropdownMenuItem<String?>(
                        value: folder.id,
                        child: Text(folder.name),
                      ),
                    ),
                  ],
                  onChanged: (String? value) {
                    setState(() {
                      parentId = value;
                    });
                  },
                ),
              ],
            );
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final String name = nameController.text.trim();
              if (name.isEmpty) {
                return;
              }
              await controller.createFolder(name: name, parentId: parentId);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      );
    },
  );

  nameController.dispose();
}
