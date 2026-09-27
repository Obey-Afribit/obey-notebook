import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../core/models/note_item.dart';
import '../../state/notebook_controller.dart';
import '../shared/sheets.dart';
import '../shared/ui.dart';
import 'note_card.dart';

/// The notes area: header (title, search, sort, layout), the selection bar
/// when selecting, and the notes themselves in sections.
class NotesView extends StatefulWidget {
  const NotesView({
    super.key,
    required this.searchFocusNode,
    required this.compact,
  });

  final FocusNode searchFocusNode;

  /// Phone layout: a menu button opens the drawer and the header is stacked.
  final bool compact;

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = context.read<NotebookController>().searchQuery;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearSearch(NotebookController controller) {
    _search.clear();
    controller.setSearchQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    if (controller.searchQuery.isEmpty && _search.text.isNotEmpty) {
      _search.clear(); // cleared elsewhere (e.g. Escape shortcut)
    }
    final List<NoteItem> notes = controller.visibleNotes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: controller.selectionMode
              ? _SelectionBar(
                  key: const ValueKey<String>('selection'),
                  controller: controller,
                  compact: widget.compact,
                )
              : _Header(
                  key: const ValueKey<String>('header'),
                  controller: controller,
                  search: _search,
                  searchFocusNode: widget.searchFocusNode,
                  compact: widget.compact,
                  onClearSearch: () => _clearSearch(controller),
                ),
        ),
        if (controller.view == NotebookView.trash && notes.isNotEmpty)
          _TrashBanner(controller: controller),
        Expanded(
          child: notes.isEmpty
              ? _EmptyForView(controller: controller)
              : _NotesScroll(controller: controller, notes: notes),
        ),
      ],
    );
  }
}

// =============================================================================
// Header
// =============================================================================

class _Header extends StatelessWidget {
  const _Header({
    super.key,
    required this.controller,
    required this.search,
    required this.searchFocusNode,
    required this.compact,
    required this.onClearSearch,
  });

  final NotebookController controller;
  final TextEditingController search;
  final FocusNode searchFocusNode;
  final bool compact;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int count = controller.visibleNotes.length;

    final Widget searchField = TextField(
      controller: search,
      focusNode: searchFocusNode,
      onChanged: controller.setSearchQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: controller.view == NotebookView.all
            ? 'Search all notes'
            : 'Search ${controller.viewTitle}',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: onClearSearch,
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );

    final Widget titleBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Flexible(
          child: Text(
            controller.viewTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$count',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );

    final List<Widget> viewActions = <Widget>[
      if (controller.view != NotebookView.reminders &&
          controller.view != NotebookView.trash)
        _SortMenu(controller: controller),
      IconButton(
        tooltip: controller.layout == NoteLayout.grid ? 'List view' : 'Grid view',
        onPressed: () => controller.setLayout(
          controller.layout == NoteLayout.grid ? NoteLayout.list : NoteLayout.grid,
        ),
        icon: Icon(
          controller.layout == NoteLayout.grid
              ? Icons.view_agenda_outlined
              : Icons.grid_view_outlined,
        ),
      ),
    ];

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
                const SizedBox(width: 4),
                Expanded(child: searchField),
                const SizedBox(width: 4),
                SyncStatusPill(controller: controller, compact: true),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 0, 0),
              child: Row(
                children: <Widget>[
                  Expanded(child: titleBlock),
                  ...viewActions,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 20, 8),
      child: Row(
        children: <Widget>[
          Expanded(child: titleBlock),
          const SizedBox(width: 16),
          SizedBox(width: 340, child: searchField),
          const SizedBox(width: 8),
          ...viewActions,
          IconButton(
            tooltip: 'Select notes',
            onPressed: controller.visibleNotes.isEmpty
                ? null
                : controller.startSelection,
            icon: const Icon(Icons.checklist_rtl),
          ),
        ],
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<NoteSort>(
      tooltip: 'Sort: ${controller.sort.label}',
      icon: const Icon(Icons.sort),
      initialValue: controller.sort,
      onSelected: controller.setSort,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<NoteSort>>[
        for (final NoteSort sort in NoteSort.values)
          CheckedPopupMenuItem<NoteSort>(
            value: sort,
            checked: controller.sort == sort,
            child: Text(sort.label),
          ),
      ],
    );
  }
}

// =============================================================================
// Selection bar
// =============================================================================

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    super.key,
    required this.controller,
    required this.compact,
  });

  final NotebookController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int count = controller.selectedCount;
    final bool any = count > 0;
    final NotebookView view = controller.view;

    Future<void> run(Future<void> Function() action) async => action();

    final List<_BarAction> actions = <_BarAction>[
      if (view == NotebookView.trash) ...<_BarAction>[
        _BarAction(Icons.restore_from_trash_outlined, 'Restore',
            () => run(controller.restoreSelected)),
        _BarAction(Icons.delete_forever_outlined, 'Delete forever', () async {
          if (await confirmAction(
            context,
            title: 'Delete $count note${count == 1 ? '' : 's'} forever?',
            message: 'They and their images will be permanently deleted.',
            confirmLabel: 'Delete',
            destructive: true,
          )) {
            await controller.deleteSelectedForever();
          }
        }),
      ] else ...<_BarAction>[
        _BarAction(Icons.push_pin_outlined, 'Pin or unpin',
            () => run(controller.togglePinSelected)),
        _BarAction(Icons.palette_outlined, 'Colour', () async {
          final ColorChoice? choice = await showNoteColorPicker(context);
          if (choice != null) {
            await controller.colorSelected(choice.colorId);
          }
        }),
        _BarAction(Icons.drive_file_move_outline, 'Move to folder', () async {
          final String? folderId = await showFolderPicker(
            context,
            controller,
            title: 'Move $count note${count == 1 ? '' : 's'} to',
          );
          if (folderId != null) {
            await controller.moveSelectedToFolder(folderId);
          }
        }),
        _BarAction(Icons.share_outlined, 'Share', () => run(controller.shareSelected)),
        if (view == NotebookView.archive)
          _BarAction(Icons.unarchive_outlined, 'Unarchive',
              () => run(controller.unarchiveSelected))
        else
          _BarAction(Icons.archive_outlined, 'Archive',
              () => run(controller.archiveSelected)),
        _BarAction(Icons.delete_outline, 'Move to trash',
            () => run(controller.moveSelectedToTrash)),
      ],
    ];

    // On phones keep the three most used actions visible, the rest in a menu.
    final int visible = compact ? 3 : actions.length;

    return Container(
      margin: EdgeInsets.fromLTRB(compact ? 8 : 20, compact ? 8 : 16, compact ? 8 : 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: IconTheme(
        data: IconThemeData(color: scheme.onPrimaryContainer),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Done',
              onPressed: controller.clearSelection,
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: Text(
                count == 0 ? 'Select notes' : '$count selected',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ),
            for (final _BarAction action in actions.take(visible))
              IconButton(
                tooltip: action.label,
                onPressed: any ? action.onTap : null,
                icon: Icon(action.icon),
              ),
            PopupMenuButton<int>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert),
              onSelected: (int index) {
                if (index < 0) {
                  controller.selectAllVisible();
                } else {
                  actions[index].onTap();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
                const PopupMenuItem<int>(
                  value: -1,
                  child: ListTile(
                    leading: Icon(Icons.select_all),
                    title: Text('Select all'),
                  ),
                ),
                for (int i = visible; i < actions.length; i++)
                  PopupMenuItem<int>(
                    value: i,
                    enabled: any,
                    child: ListTile(
                      leading: Icon(actions[i].icon),
                      title: Text(actions[i].label),
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

class _BarAction {
  const _BarAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

// =============================================================================
// Content
// =============================================================================

class _NotesScroll extends StatelessWidget {
  const _NotesScroll({required this.controller, required this.notes});

  final NotebookController controller;
  final List<NoteItem> notes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double gutter = width < Breakpoints.sidebar ? 12 : 28;
        final int columns = width < 330
            ? 1
            : ((width - gutter * 2) / 250).floor().clamp(2, 6);

        final List<(String?, List<NoteItem>)> sections = _sections();

        return Scrollbar(
          child: CustomScrollView(
            slivers: <Widget>[
              for (final (String? label, List<NoteItem> items) in sections) ...<Widget>[
                if (label != null)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    sliver: SliverToBoxAdapter(child: SectionLabel(label)),
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  sliver: controller.layout == NoteLayout.list
                      ? SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (BuildContext context, int index) =>
                              NoteCard(
                            key: ValueKey<String>(items[index].id),
                            note: items[index],
                            controller: controller,
                            dense: true,
                          ),
                        )
                      : SliverMasonryGrid.count(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childCount: items.length,
                          itemBuilder: (BuildContext context, int index) =>
                              NoteCard(
                            key: ValueKey<String>(items[index].id),
                            note: items[index],
                            controller: controller,
                          ),
                        ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 112)),
            ],
          ),
        );
      },
    );
  }

  List<(String?, List<NoteItem>)> _sections() {
    if (controller.view == NotebookView.reminders) {
      final DateTime now = DateTime.now();
      final List<NoteItem> upcoming =
          notes.where((NoteItem n) => n.reminderAt!.isAfter(now)).toList();
      final List<NoteItem> past = notes
          .where((NoteItem n) => !n.reminderAt!.isAfter(now))
          .toList()
          .reversed
          .toList();
      return <(String?, List<NoteItem>)>[
        if (upcoming.isNotEmpty) ('Upcoming', upcoming),
        if (past.isNotEmpty) ('Past', past),
      ];
    }
    if (!controller.showsPinnedSection || controller.searchQuery.isNotEmpty) {
      return <(String?, List<NoteItem>)>[(null, notes)];
    }
    final List<NoteItem> pinned = notes.where((NoteItem n) => n.isPinned).toList();
    if (pinned.isEmpty) {
      return <(String?, List<NoteItem>)>[(null, notes)];
    }
    final List<NoteItem> others = notes.where((NoteItem n) => !n.isPinned).toList();
    return <(String?, List<NoteItem>)>[
      ('Pinned', pinned),
      if (others.isNotEmpty) ('Others', others),
    ];
  }
}

class _TrashBanner extends StatelessWidget {
  const _TrashBanner({required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Notes in the trash are deleted forever after 30 days.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () async {
              if (await confirmAction(
                context,
                title: 'Empty trash?',
                message: 'All ${controller.trashCount} notes in the trash and '
                    'their images will be permanently deleted.',
                confirmLabel: 'Empty trash',
                destructive: true,
              )) {
                await controller.emptyTrash();
              }
            },
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
  }
}

class _EmptyForView extends StatelessWidget {
  const _EmptyForView({required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.searchQuery.trim().isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No matches',
        message: 'Nothing in ${controller.viewTitle} matches '
            '"${controller.searchQuery.trim()}".',
      );
    }
    switch (controller.view) {
      case NotebookView.all:
        return const EmptyState(
          icon: Icons.edit_note,
          title: 'Your notebook is empty',
          message: 'Capture ideas, lists and photos. Tap New note to start.',
        );
      case NotebookView.pinned:
        return const EmptyState(
          icon: Icons.push_pin_outlined,
          title: 'Nothing pinned',
          message: 'Pin the notes you use most to keep them at the top.',
        );
      case NotebookView.reminders:
        return const EmptyState(
          icon: Icons.alarm,
          title: 'No reminders',
          message: 'Set a reminder on any note and it will appear here.',
        );
      case NotebookView.archive:
        return const EmptyState(
          icon: Icons.archive_outlined,
          title: 'Archive is empty',
          message:
              'Archived notes stay out of the way but still turn up in search.',
        );
      case NotebookView.trash:
        return const EmptyState(
          icon: Icons.delete_outline,
          title: 'Trash is empty',
          message: 'Deleted notes wait here for 30 days before they go.',
        );
      case NotebookView.folder:
        return const EmptyState(
          icon: Icons.folder_open_outlined,
          title: 'This folder is empty',
          message: 'Notes you create while here are saved in this folder.',
        );
      case NotebookView.tag:
        return const EmptyState(
          icon: Icons.tag,
          title: 'No notes with this tag',
          message: 'Add tags to a note from its menu in the editor.',
        );
    }
  }
}
