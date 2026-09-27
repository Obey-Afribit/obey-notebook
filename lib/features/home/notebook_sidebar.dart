import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/models/folder_item.dart';
import '../../state/notebook_controller.dart';
import '../shared/sheets.dart';
import '../shared/ui.dart';

enum HomeSection { notes, templates, settings }

/// Navigation for the whole app. Permanent on wide screens, a drawer on
/// phones ([inDrawer] closes the drawer after each choice).
class NotebookSidebar extends StatelessWidget {
  const NotebookSidebar({
    super.key,
    required this.section,
    required this.onSection,
    required this.onNewNote,
    this.inDrawer = false,
  });

  final HomeSection section;
  final ValueChanged<HomeSection> onSection;
  final VoidCallback onNewNote;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool notes = section == HomeSection.notes;

    void go(VoidCallback action, [HomeSection target = HomeSection.notes]) {
      action();
      onSection(target);
      if (inDrawer) {
        Navigator.of(context).maybePop();
      }
    }

    Widget view(NotebookView v, IconData icon, IconData selectedIcon,
        String label, int count) {
      final bool selected = notes && controller.view == v;
      return _NavTile(
        icon: selected ? selectedIcon : icon,
        label: label,
        count: count,
        selected: selected,
        onTap: () => go(() => controller.openView(v)),
      );
    }

    final List<MapEntry<String, int>> tags = controller.tagCounts;

    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: <Widget>[
                  const BrandMark(size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppConfig.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (!inDrawer)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: FilledButton.icon(
                  onPressed: onNewNote,
                  icon: const Icon(Icons.add),
                  label: const Text('New note'),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                children: <Widget>[
                  view(NotebookView.all, Icons.notes_outlined, Icons.notes,
                      'All notes', controller.allCount),
                  view(NotebookView.pinned, Icons.push_pin_outlined,
                      Icons.push_pin, 'Pinned', controller.pinnedCount),
                  view(NotebookView.reminders, Icons.alarm_outlined,
                      Icons.alarm, 'Reminders', controller.remindersCount),
                  view(NotebookView.archive, Icons.archive_outlined,
                      Icons.archive, 'Archive', controller.archiveCount),
                  view(NotebookView.trash, Icons.delete_outline, Icons.delete,
                      'Trash', controller.trashCount),
                  SectionLabel(
                    'Folders',
                    padding: const EdgeInsets.fromLTRB(12, 18, 0, 4),
                    trailing: IconButton(
                      tooltip: 'New folder',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _createFolder(context, controller, null),
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ),
                  ..._folderTiles(context, controller, null, 0, notes, go),
                  if (tags.isNotEmpty) ...<Widget>[
                    const SectionLabel(
                      'Tags',
                      padding: EdgeInsets.fromLTRB(12, 18, 0, 8),
                    ),
                    for (final MapEntry<String, int> tag in tags)
                      _NavTile(
                        icon: Icons.tag,
                        label: tag.key,
                        count: tag.value,
                        selected: notes &&
                            controller.view == NotebookView.tag &&
                            controller.selectedTag == tag.key,
                        onTap: () => go(() => controller.openTag(tag.key)),
                      ),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  _NavTile(
                    icon: section == HomeSection.templates
                        ? Icons.dashboard_customize
                        : Icons.dashboard_customize_outlined,
                    label: 'Templates',
                    selected: section == HomeSection.templates,
                    onTap: () => go(() {}, HomeSection.templates),
                  ),
                  _NavTile(
                    icon: section == HomeSection.settings
                        ? Icons.settings
                        : Icons.settings_outlined,
                    label: 'Settings',
                    selected: section == HomeSection.settings,
                    onTap: () => go(() {}, HomeSection.settings),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SyncStatusPill(controller: controller),
                  if (controller.accountEmail != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Text(
                        controller.accountEmail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _folderTiles(
    BuildContext context,
    NotebookController controller,
    String? parentId,
    int depth,
    bool notesSection,
    void Function(VoidCallback action, [HomeSection target]) go,
  ) {
    final List<Widget> tiles = <Widget>[];
    for (final FolderItem folder in controller.childFolders(parentId)) {
      final bool selected = notesSection &&
          controller.view == NotebookView.folder &&
          controller.selectedFolderId == folder.id;
      final bool locked = controller.isFolderLocked(folder.id);
      tiles.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 14.0),
          child: _NavTile(
            icon: locked
                ? Icons.lock_outline
                : (selected ? Icons.folder : Icons.folder_outlined),
            label: folder.name,
            count: controller.folderNoteCount(folder.id),
            selected: selected,
            onTap: () async {
              final bool opened = await controller.openFolder(folder.id);
              if (!opened) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder stays locked.')),
                  );
                }
                return;
              }
              go(() {});
            },
            menu: _FolderMenu(folder: folder, controller: controller),
          ),
        ),
      );
      tiles.addAll(
        _folderTiles(context, controller, folder.id, depth + 1, notesSection, go),
      );
    }
    return tiles;
  }
}

Future<void> _createFolder(
  BuildContext context,
  NotebookController controller,
  String? parentId,
) async {
  final String? name = await showNameDialog(
    context,
    title: parentId == null ? 'New folder' : 'New sub-folder',
    label: 'Folder name',
    confirmLabel: 'Create',
  );
  if (name != null) {
    await controller.createFolder(name: name, parentId: parentId);
  }
}

class _FolderMenu extends StatelessWidget {
  const _FolderMenu({required this.folder, required this.controller});

  final FolderItem folder;
  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    final bool locked = controller.lockedFolderIds.contains(folder.id);
    return PopupMenuButton<String>(
      tooltip: 'Folder options',
      icon: const Icon(Icons.more_horiz, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (String value) async {
        switch (value) {
          case 'rename':
            final String? name = await showNameDialog(
              context,
              title: 'Rename folder',
              label: 'Folder name',
              initial: folder.name,
            );
            if (name != null) {
              await controller.renameFolder(folder.id, name);
            }
            break;
          case 'sub':
            await _createFolder(context, controller, folder.id);
            break;
          case 'lock':
            await controller.toggleFolderLock(folder.id);
            break;
          case 'delete':
            final int count = controller.folderNoteCount(folder.id);
            if (await confirmAction(
              context,
              title: 'Delete "${folder.name}"?',
              message: count == 0
                  ? 'The folder will be removed.'
                  : 'Its $count note${count == 1 ? '' : 's'} will move to the '
                      'trash, where you can restore them for 30 days.',
              confirmLabel: 'Delete folder',
              destructive: true,
            )) {
              await controller.deleteFolder(folder.id);
            }
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename')),
        ),
        const PopupMenuItem<String>(
          value: 'sub',
          child: ListTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('New sub-folder'),
          ),
        ),
        if (controller.lockSupported)
          PopupMenuItem<String>(
            value: 'lock',
            child: ListTile(
              leading: Icon(locked ? Icons.lock_open_outlined : Icons.lock_outline),
              title: Text(locked ? 'Remove lock' : 'Lock folder'),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.menu,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 0, menu == null ? 14 : 2, 0),
              child: Row(
                children: <Widget>[
                  Icon(icon,
                      size: 20,
                      color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: fg,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (count != null && count! > 0)
                    Text(
                      '$count',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  if (menu != null) SizedBox(width: 36, height: 36, child: menu),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
