import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/markdown_tools.dart';
import '../../core/models/note_item.dart';
import '../../core/theme/note_colors.dart';
import '../../state/notebook_controller.dart';
import '../shared/sheets.dart';
import '../shared/ui.dart';
import 'note_editor_screen.dart';

/// Opens a note in the editor.
Future<void> openNote(BuildContext context, String noteId, {bool isNew = false}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NoteEditorScreen(noteId: noteId, isNew: isNew),
    ),
  );
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.controller,
    this.dense = false,
  });

  final NoteItem note;
  final NotebookController controller;

  /// List layout: one row per note instead of a masonry card.
  final bool dense;

  void _handleTap(BuildContext context) {
    final bool modifier = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (controller.selectionMode || modifier) {
      if (controller.selectionMode) {
        controller.toggleNoteSelection(note.id);
      } else {
        controller.enterSelectionMode(note.id);
      }
      return;
    }
    openNote(context, note.id);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color? tint = NoteColors.backgroundFor(note.colorId, theme.brightness);
    final bool selected = controller.isNoteSelected(note.id);

    final Widget content = dense
        ? _DenseBody(note: note, controller: controller, selected: selected)
        : _CardBody(note: note, controller: controller, selected: selected);

    return Semantics(
      button: true,
      selected: selected,
      label: note.displayTitle.isEmpty ? 'Untitled note' : note.displayTitle,
      child: Material(
        color: tint ?? scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dense ? 14 : 16),
          side: selected
              ? BorderSide(color: scheme.primary, width: 2)
              : (tint == null
                  ? BorderSide(color: scheme.outlineVariant)
                  : BorderSide.none),
        ),
        child: InkWell(
          onTap: () => _handleTap(context),
          onLongPress: controller.selectionMode
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  controller.enterSelectionMode(note.id);
                },
          onSecondaryTapUp: (TapUpDetails details) =>
              showNoteContextMenu(context, controller, note, details.globalPosition),
          child: content,
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.note,
    required this.controller,
    required this.selected,
  });

  final NoteItem note;
  final NotebookController controller;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String title = note.displayTitle;
    final String preview = MarkdownTools.previewText(note.body);
    final TaskProgress tasks = MarkdownTools.taskProgress(note.body);
    final List<String> images = <String>[
      ...MarkdownTools.imageUrls(note.body),
      ...note.imagePaths,
    ].where((String url) => url.startsWith('http')).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (images.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 170),
            child: Image.network(
              images.first,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              loadingBuilder: (BuildContext context, Widget child,
                  ImageChunkEvent? progress) {
                if (progress == null) {
                  return child;
                }
                return Container(height: 120, color: scheme.surfaceContainerHigh);
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title.isNotEmpty || controller.selectionMode || note.isPinned)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (controller.selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 1),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: selected ? scheme.primary : scheme.outline,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title.isEmpty ? 'Untitled' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: title.isEmpty ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                    if (note.isPinned)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, top: 2),
                        child:
                            Icon(Icons.push_pin, size: 16, color: scheme.primary),
                      ),
                  ],
                ),
              if (preview.isNotEmpty) ...<Widget>[
                if (title.isNotEmpty) const SizedBox(height: 6),
                Text(
                  preview,
                  maxLines: images.isEmpty ? 9 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (tasks.hasTasks) ...<Widget>[
                const SizedBox(height: 10),
                _TaskMeter(progress: tasks),
              ],
              const SizedBox(height: 10),
              _CardFooter(note: note, controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}

class _DenseBody extends StatelessWidget {
  const _DenseBody({
    required this.note,
    required this.controller,
    required this.selected,
  });

  final NoteItem note;
  final NotebookController controller;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String title = note.displayTitle;
    final String preview =
        MarkdownTools.previewText(note.body).replaceAll('\n', '  ');
    final TaskProgress tasks = MarkdownTools.taskProgress(note.body);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: <Widget>[
          if (controller.selectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title.isEmpty ? 'Untitled' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: title.isEmpty ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      relativeTime(note.updatedAt),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (preview.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (note.isPinned) ...<Widget>[
            const SizedBox(width: 10),
            Icon(Icons.push_pin, size: 16, color: scheme.primary),
          ],
          if (note.reminderAt != null) ...<Widget>[
            const SizedBox(width: 10),
            Icon(Icons.alarm, size: 16, color: scheme.onSurfaceVariant),
          ],
          if (tasks.hasTasks) ...<Widget>[
            const SizedBox(width: 10),
            Text(
              '${tasks.done}/${tasks.total}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskMeter extends StatelessWidget {
  const _TaskMeter({required this.progress});

  final TaskProgress progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool complete = progress.done == progress.total;
    return Row(
      children: <Widget>[
        Icon(
          complete ? Icons.check_circle : Icons.checklist,
          size: 16,
          color: complete ? scheme.tertiary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          '${progress.done} of ${progress.total}',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.total == 0 ? 0 : progress.done / progress.total,
              minHeight: 4,
              color: complete ? scheme.tertiary : scheme.primary,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.note, required this.controller});

  final NoteItem note;
  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? meta =
        theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final bool overdue =
        note.reminderAt != null && note.reminderAt!.isBefore(DateTime.now());

    final List<Widget> chips = <Widget>[
      if (note.reminderAt != null)
        _MiniChip(
          icon: overdue ? Icons.alarm_off : Icons.alarm,
          label: reminderLabel(note.reminderAt!),
          color: overdue ? scheme.error : null,
        ),
      for (final String tag in note.tags.take(3)) _MiniChip(label: '#$tag'),
      if (note.tags.length > 3) _MiniChip(label: '+${note.tags.length - 3}'),
      if (controller.view != NotebookView.folder &&
          controller.folders.length > 1 &&
          controller.folderById(note.folderId) != null)
        _MiniChip(
          icon: Icons.folder_outlined,
          label: controller.folderById(note.folderId)!.name,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (chips.isNotEmpty) ...<Widget>[
          Wrap(spacing: 6, runSpacing: 6, children: chips),
          const SizedBox(height: 8),
        ],
        Text(
          note.isDeleted && note.deletedAt != null
              ? 'Deleted ${relativeTime(note.deletedAt!).toLowerCase()}'
              : relativeTime(note.updatedAt),
          style: meta,
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fg = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Right-click menu for a note (desktop and web).
Future<void> showNoteContextMenu(
  BuildContext context,
  NotebookController controller,
  NoteItem note,
  Offset position,
) async {
  final RenderBox overlay =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final String? action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: note.isDeleted
        ? const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'restore',
              child: ListTile(
                leading: Icon(Icons.restore_from_trash_outlined),
                title: Text('Restore'),
              ),
            ),
            PopupMenuItem<String>(
              value: 'forever',
              child: ListTile(
                leading: Icon(Icons.delete_forever_outlined),
                title: Text('Delete forever'),
              ),
            ),
          ]
        : <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'open',
              child: ListTile(
                leading: Icon(Icons.open_in_new),
                title: Text('Open'),
              ),
            ),
            PopupMenuItem<String>(
              value: 'pin',
              child: ListTile(
                leading: Icon(note.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                title: Text(note.isPinned ? 'Unpin' : 'Pin'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'color',
              child: ListTile(
                leading: Icon(Icons.palette_outlined),
                title: Text('Colour'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'move',
              child: ListTile(
                leading: Icon(Icons.drive_file_move_outline),
                title: Text('Move to folder'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'select',
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Select'),
              ),
            ),
            PopupMenuItem<String>(
              value: 'archive',
              child: ListTile(
                leading: Icon(note.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined),
                title: Text(note.isArchived ? 'Unarchive' : 'Archive'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'trash',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Move to trash'),
              ),
            ),
          ],
  );
  if (action == null || !context.mounted) {
    return;
  }
  switch (action) {
    case 'open':
      await openNote(context, note.id);
      break;
    case 'pin':
      await controller.togglePin(note);
      break;
    case 'color':
      final ColorChoice? choice =
          await showNoteColorPicker(context, current: note.colorId);
      if (choice != null) {
        await controller.setNoteColor(note, choice.colorId);
      }
      break;
    case 'move':
      final String? folderId = await showFolderPicker(
        context,
        controller,
        currentFolderId: note.folderId,
      );
      if (folderId != null) {
        await controller.moveNoteToFolder(note, folderId);
      }
      break;
    case 'select':
      controller.enterSelectionMode(note.id);
      break;
    case 'archive':
      note.isArchived
          ? await controller.unarchiveNote(note)
          : await controller.archiveNote(note);
      break;
    case 'trash':
      await controller.moveToTrash(note);
      break;
    case 'restore':
      await controller.restoreFromTrash(note);
      break;
    case 'forever':
      if (await confirmAction(
        context,
        title: 'Delete forever?',
        message: 'This note and its images will be permanently deleted.',
        confirmLabel: 'Delete',
        destructive: true,
      )) {
        await controller.permanentlyDeleteNote(note.id);
      }
      break;
  }
}
