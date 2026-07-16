import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_controller.dart';
import '../../state/notebook_controller.dart';
import '../notes/note_editor_screen.dart';
import '../notes/notes_dashboard.dart';
import '../settings/settings_screen.dart';
import '../templates/templates_screen.dart';

class NotebookHomeScreen extends StatefulWidget {
  const NotebookHomeScreen({super.key});

  @override
  State<NotebookHomeScreen> createState() => _NotebookHomeScreenState();
}

class _NotebookHomeScreenState extends State<NotebookHomeScreen> {
  int _tabIndex = 0;

  static const List<_NavItem> _navItems = <_NavItem>[
    _NavItem(Icons.notes_outlined, Icons.notes, 'Notes'),
    _NavItem(Icons.dashboard_customize_outlined, Icons.dashboard_customize,
        'Templates'),
    _NavItem(Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  Future<void> _openQuickCaptureDialog(BuildContext context) async {
    final TextEditingController quickController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Quick capture'),
          content: SizedBox(
            width: 460,
            child: TextField(
              controller: quickController,
              minLines: 4,
              maxLines: 8,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Type a quick thought, todo, or idea...',
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final String text = quickController.text.trim();
                if (text.isEmpty) {
                  return;
                }
                final note = await context
                    .read<NotebookController>()
                    .quickCaptureNote(text);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (!context.mounted) {
                  return;
                }
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        NoteEditorScreen(noteId: note.id),
                  ),
                );
              },
              child: const Text('Capture'),
            ),
          ],
        );
      },
    );

    quickController.dispose();
  }

  Future<void> _createAndOpenNote(BuildContext context) async {
    final NotebookController controller = context.read<NotebookController>();
    final note =
        await controller.createBlankNote(folderId: controller.selectedFolderId);

    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => NoteEditorScreen(noteId: note.id),
      ),
    );
  }

  void _cycleThemeMode(ThemeController theme) {
    final ThemeMode next;
    switch (theme.themeMode) {
      case ThemeMode.system:
        next = ThemeMode.light;
        break;
      case ThemeMode.light:
        next = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        next = ThemeMode.system;
        break;
    }
    theme.setThemeMode(next);
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeController themeController = context.watch<ThemeController>();

    final List<Widget> tabs = <Widget>[
      const NotesDashboard(),
      const TemplatesScreen(),
      const SettingsScreen(),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 800;

        final List<Widget> appBarActions = <Widget>[
          IconButton(
            tooltip: 'Quick capture',
            onPressed: () => _openQuickCaptureDialog(context),
            icon: const Icon(Icons.bolt_outlined),
          ),
          IconButton(
            tooltip: 'Theme: ${themeController.themeMode.name}',
            onPressed: () => _cycleThemeMode(themeController),
            icon: Icon(_themeModeIcon(themeController.themeMode)),
          ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: controller.isBusy
                ? null
                : () async {
                    final bool synced = await controller.syncNow();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          synced
                              ? 'Synced successfully.'
                              : 'Sync pending. You may be offline.',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.sync),
          ),
          const SizedBox(width: 4),
        ];

        final Widget? fab = _tabIndex == 0
            ? FloatingActionButton.extended(
                onPressed: () => _createAndOpenNote(context),
                icon: const Icon(Icons.add),
                label: const Text('New note'),
              )
            : null;

        if (wide) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Universal Notebook'),
              actions: appBarActions,
            ),
            floatingActionButton: fab,
            body: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (int index) =>
                      setState(() => _tabIndex = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: _navItems
                      .map(
                        (_NavItem item) => NavigationRailDestination(
                          icon: Icon(item.icon),
                          selectedIcon: Icon(item.selectedIcon),
                          label: Text(item.label),
                        ),
                      )
                      .toList(growable: false),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: tabs[_tabIndex]),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Universal Notebook'),
            actions: appBarActions,
          ),
          body: tabs[_tabIndex],
          floatingActionButton: fab,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (int index) =>
                setState(() => _tabIndex = index),
            destinations: _navItems
                .map(
                  (_NavItem item) => NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
