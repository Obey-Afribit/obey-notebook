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

  Future<void> _openQuickCaptureDialog(BuildContext context) async {
    final TextEditingController quickController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Quick Capture'),
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

                if (!mounted) {
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
    final note = await controller.createBlankNote(folderId: controller.selectedFolderId);

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => NoteEditorScreen(noteId: note.id),
      ),
    );
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

    return Container(
      decoration: themeController.buildBackgroundDecoration(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Universal Notebook'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Quick capture',
              onPressed: () => _openQuickCaptureDialog(context),
              icon: const Icon(Icons.bolt_outlined),
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
          ],
        ),
        body: tabs[_tabIndex],
        floatingActionButton: _tabIndex == 0
            ? FloatingActionButton.extended(
                onPressed: () => _createAndOpenNote(context),
                icon: const Icon(Icons.note_add),
                label: const Text('New Note'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          destinations: const <Widget>[
            NavigationDestination(
              icon: Icon(Icons.edit_note),
              label: 'Notes',
            ),
            NavigationDestination(
              icon: Icon(Icons.widgets_outlined),
              label: 'Templates',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
          onDestinationSelected: (int index) {
            setState(() {
              _tabIndex = index;
            });
          },
        ),
      ),
    );
  }
}
