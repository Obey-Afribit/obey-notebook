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

    return PopScope(
      canPop: !controller.selectionMode,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && controller.selectionMode) {
          controller.clearSelection();
        }
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth > 900;

          if (wide) {
            return Row(
              children: <Widget>[
                SizedBox(
                    width: 288, child: _FolderPanel(controller: controller)),
                const VerticalDivider(width: 1),
                Expanded(child: _NotesPanel(controller: controller)),
              ],
            );
          }

          return Column(
            children: <Widget>[
              _CompactFolderSelector(controller: controller),
              const Divider(height: 1),
              Expanded(child: _NotesPanel(controller: controller)),
            ],
          );
        },
      ),
    );
  }
}

/// Turns Markdown source into a clean one-glance preview snippet.
String _previewText(String body) {
  final String stripped = body
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '') // inline images
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'[*_`~]'), '')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
  return stripped;
}

class _CompactFolderSelector extends StatelessWidget {
  const _CompactFolderSelector({required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: controller.selectedFolderId,
              decoration: const InputDecoration(
                labelText: 'Folder',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: controller.folders
                  .map(
                    (FolderItem folder) => DropdownMenuItem<String?>(
                      value: folder.id,
                      child: Text(folder.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: controller.selectFolder,
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: 'New folder',
            onPressed: () => _showCreateFolderDialog(context, controller),
            icon: const Icon(Icons.create_new_folder_outlined),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
            child: Row(
              children: <Widget>[
                Text(
                  'Folders',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'New folder',
                  onPressed: () => _showCreateFolderDialog(context, controller),
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
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
    final ColorScheme scheme = Theme.of(context).colorScheme;

    for (final FolderItem folder in children) {
      final bool isSelected = controller.selectedFolderId == folder.id;
      final bool isLocked = controller.isFolderLocked(folder.id);

      widgets.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 14, bottom: 2),
          child: Material(
            color: isSelected
                ? scheme.primaryContainer.withValues(alpha: 0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(
                isLocked ? Icons.lock_outline : Icons.folder_outlined,
                color: isSelected ? scheme.onPrimaryContainer : null,
                size: 20,
              ),
              title: Text(
                folder.name,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 18),
                tooltip: 'Folder actions',
                onSelected: (String value) {
                  if (value == 'lock') {
                    controller.toggleFolderLock(folder.id);
                  } else if (value == 'delete') {
                    controller.deleteFolder(folder.id);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'lock',
                    child: Text(isLocked ? 'Remove lock' : 'Lock folder'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete folder'),
                  ),
                ],
              ),
              onTap: () => controller.selectFolder(folder.id),
            ),
          ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!controller.cloudConfigured)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _InfoBanner(
              text:
                  'Local-only mode. Notes are saved on this device; enable cloud sync any time.',
              actionLabel: 'Retry',
              onAction: controller.isBusy ? null : controller.retryCloudSetup,
            ),
          ),
        if (controller.selectionMode)
          _SelectionBar(controller: controller)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: <Widget>[
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search notes, tags, content...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: controller.setSearchQuery,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            FilterChip(
                              label: const Text('Archived'),
                              selected: controller.showArchived,
                              onSelected: controller.setShowArchived,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('Has images'),
                              selected: controller.hasImageFilter,
                              onSelected: controller.setHasImageFilter,
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.date_range, size: 18),
                              label: Text(
                                controller.filterStartDate == null
                                    ? 'Date'
                                    : 'Date set',
                              ),
                              onPressed: () =>
                                  _showDateFilter(context, controller),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(Icons.delete_outline, size: 18),
                      label: Text('Trash (${controller.trashNotes.length})'),
                      onPressed: () => _showTrashDialog(context, controller),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: notes.isEmpty
              ? const _EmptyState()
              : _NotesGrid(notes: notes, controller: controller),
        ),
      ],
    );
  }
}

class _NotesGrid extends StatelessWidget {
  const _NotesGrid({required this.notes, required this.controller});

  final List<NoteItem> notes;
  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = (constraints.maxWidth / 320).floor().clamp(1, 4);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 168,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: notes.length,
          itemBuilder: (BuildContext context, int index) {
            return _NoteCard(note: notes[index], controller: controller);
          },
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.controller});

  final NoteItem note;
  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String preview = _previewText(note.body);
    final String updated =
        DateFormat('d MMM, HH:mm').format(note.updatedAt.toLocal());
    final bool isConflict = note.conflictGroupId != null;
    final bool selectionMode = controller.selectionMode;
    final bool selected = controller.isNoteSelected(note.id);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: () {
          if (selectionMode) {
            controller.toggleNoteSelection(note.id);
          } else {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NoteEditorScreen(noteId: note.id),
              ),
            );
          }
        },
        onLongPress: selectionMode
            ? null
            : () => controller.enterSelectionMode(note.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color:
                            selected ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  if (isConflict)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.warning_amber_rounded,
                          size: 18, color: scheme.error),
                    ),
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (note.isPinned)
                    Icon(Icons.push_pin, size: 16, color: scheme.primary),
                  if (!selectionMode)
                    _NoteMenu(note: note, controller: controller),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  preview.isEmpty ? 'Empty note' : preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Text(
                    updated,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const Spacer(),
                  if (note.imagePaths.isNotEmpty) ...<Widget>[
                    Icon(Icons.image_outlined,
                        size: 15, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text('${note.imagePaths.length}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 8),
                  ],
                  if (note.reminderAt != null)
                    Icon(Icons.alarm, size: 15, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteMenu extends StatelessWidget {
  const _NoteMenu({required this.note, required this.controller});

  final NoteItem note;
  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: 'Note actions',
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
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'share', child: Text('Share')),
        PopupMenuItem<String>(
          value: 'pin',
          child: Text(note.isPinned ? 'Unpin' : 'Pin'),
        ),
        PopupMenuItem<String>(
          value: 'archive',
          child: Text(note.isArchived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuItem<String>(
          value: 'trash',
          child: Text('Move to trash'),
        ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int count = controller.selectedCount;
    final bool hasSelection = count > 0;

    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: controller.clearSelection,
            ),
            Expanded(
              child: Text(
                '$count selected',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
              ),
            ),
            IconButton(
              tooltip: 'Move to folder',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed:
                  hasSelection ? () => _showMoveSheet(context, controller) : null,
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
              onPressed: hasSelection ? controller.shareSelected : null,
            ),
            IconButton(
              tooltip: 'Move to trash',
              icon: const Icon(Icons.delete_outline),
              onPressed: hasSelection
                  ? () => _confirmBulkDelete(context, controller)
                  : null,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert),
              onSelected: (String value) {
                switch (value) {
                  case 'select_all':
                    controller.selectAllNotes(
                      controller.filteredNotes
                          .map((NoteItem note) => note.id),
                    );
                    break;
                  case 'archive':
                    controller.archiveSelected();
                    break;
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'select_all',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.select_all),
                    title: Text('Select all'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'archive',
                  enabled: hasSelection,
                  child: const ListTile(
                    dense: true,
                    leading: Icon(Icons.archive_outlined),
                    title: Text('Archive'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.edit_note,
              size: 72, color: scheme.primary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            'No notes here yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the New note button to start writing.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off_outlined,
              size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

Future<void> _showMoveSheet(
  BuildContext context,
  NotebookController controller,
) async {
  final int count = controller.selectedCount;
  final String? folderId = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Move $count note${count == 1 ? '' : 's'} to...',
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: controller.folders
                    .map(
                      (FolderItem folder) => ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(folder.name),
                        onTap: () =>
                            Navigator.of(sheetContext).pop(folder.id),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (folderId != null) {
    await controller.moveSelectedToFolder(folderId);
  }
}

Future<void> _confirmBulkDelete(
  BuildContext context,
  NotebookController controller,
) async {
  final int count = controller.selectedCount;
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text('Move $count note${count == 1 ? '' : 's'} to trash?'),
        content: const Text('You can restore them from Trash afterwards.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Move to trash'),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    await controller.moveSelectedToTrash();
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
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Trash is empty.')),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: controller.trashNotes.length,
                  itemBuilder: (BuildContext context, int index) {
                    final NoteItem note = controller.trashNotes[index];
                    return ListTile(
                      title: Text(note.title),
                      subtitle: Text(
                        _previewText(note.body),
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
            onPressed: () {
              controller.setDateFilter(startDate: null, endDate: null);
              controller.setHasImageFilter(false);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Clear filters'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
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
        title: const Text('Create folder'),
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
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Folder name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: parentId,
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
                  onChanged: (String? value) =>
                      setState(() => parentId = value),
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
