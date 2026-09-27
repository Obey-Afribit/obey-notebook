import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/markdown_tools.dart';
import '../../core/models/note_item.dart';
import '../../state/notebook_controller.dart';
import '../notes/note_card.dart';
import '../notes/notes_view.dart';
import '../settings/settings_screen.dart';
import '../shared/ui.dart';
import '../templates/templates_screen.dart';
import 'notebook_sidebar.dart';

class NotebookHomeScreen extends StatefulWidget {
  const NotebookHomeScreen({super.key});

  @override
  State<NotebookHomeScreen> createState() => _NotebookHomeScreenState();
}

class _NotebookHomeScreenState extends State<NotebookHomeScreen> {
  HomeSection _section = HomeSection.notes;
  final FocusNode _searchFocus = FocusNode();
  late final NotebookController _controller;
  bool _alertOpen = false;
  bool _recoveryOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = context.read<NotebookController>();
    _controller.reminderAlerts.addListener(_onReminderAlerts);
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onReminderAlerts();
      _onControllerChanged();
    });
  }

  @override
  void dispose() {
    _controller.reminderAlerts.removeListener(_onReminderAlerts);
    _controller.removeListener(_onControllerChanged);
    _searchFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _newNote() async {
    if (_controller.view == NotebookView.trash ||
        _controller.view == NotebookView.archive) {
      _controller.openView(NotebookView.all);
    }
    setState(() => _section = HomeSection.notes);
    final NoteItem note = await _controller.createNote();
    if (mounted) {
      await openNote(context, note.id, isNew: true);
    }
  }

  void _focusSearch() {
    setState(() => _section = HomeSection.notes);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _escape() {
    if (_controller.selectionMode) {
      _controller.clearSelection();
    } else if (_controller.searchQuery.isNotEmpty) {
      _controller.setSearchQuery('');
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // ---------------------------------------------------------------------------
  // In-app reminders (Windows and web) and password recovery
  // ---------------------------------------------------------------------------

  Future<void> _onReminderAlerts() async {
    if (_alertOpen || !mounted) {
      return;
    }
    final List<NoteItem> alerts = _controller.reminderAlerts.value;
    if (alerts.isEmpty) {
      return;
    }
    _alertOpen = true;
    final NoteItem note = alerts.first;
    final String? choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final String preview = MarkdownTools.previewText(note.body);
        return AlertDialog(
          icon: const Icon(Icons.alarm),
          title: Text(note.displayTitle.isEmpty ? 'Reminder' : note.displayTitle),
          content: preview.isEmpty
              ? null
              : Text(preview, maxLines: 4, overflow: TextOverflow.ellipsis),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('snooze'),
              child: const Text('Snooze 10 min'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('dismiss'),
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('open'),
              child: const Text('Open note'),
            ),
          ],
        );
      },
    );
    _controller.dismissReminderAlert(note);
    _alertOpen = false;
    if (!mounted) {
      return;
    }
    if (choice == 'snooze') {
      await _controller.setReminder(
        note,
        DateTime.now().add(const Duration(minutes: 10)),
      );
    } else if (choice == 'open') {
      await openNote(context, note.id);
    }
    _onReminderAlerts(); // show the next one, if any
  }

  void _onControllerChanged() {
    if (!mounted || _recoveryOpen || !_controller.passwordRecoveryPending) {
      return;
    }
    _recoveryOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _NewPasswordDialog(),
      );
      _recoveryOpen = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  Widget _content(bool compact) {
    switch (_section) {
      case HomeSection.notes:
        return NotesView(searchFocusNode: _searchFocus, compact: compact);
      case HomeSection.templates:
        return TemplatesView(compact: compact);
      case HomeSection.settings:
        return SettingsView(compact: compact);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newNote,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newNote,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= Breakpoints.sidebar;
            final bool canCreate = _section == HomeSection.notes &&
                controller.view != NotebookView.trash &&
                !controller.selectionMode;

            final Widget sidebar = NotebookSidebar(
              section: _section,
              onSection: (HomeSection s) => setState(() => _section = s),
              onNewNote: _newNote,
              inDrawer: !wide,
            );

            if (wide) {
              return Scaffold(
                body: Row(
                  children: <Widget>[
                    SizedBox(width: 284, child: sidebar),
                    const VerticalDivider(width: 1),
                    Expanded(child: SafeArea(left: false, child: _content(false))),
                  ],
                ),
              );
            }

            return PopScope(
              canPop: !controller.selectionMode,
              onPopInvokedWithResult: (bool didPop, Object? result) {
                if (!didPop && controller.selectionMode) {
                  controller.clearSelection();
                }
              },
              child: Scaffold(
                drawer: Drawer(width: 300, child: sidebar),
                body: SafeArea(bottom: false, child: _content(true)),
                floatingActionButton: canCreate
                    ? FloatingActionButton.extended(
                        onPressed: _newNote,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('New note'),
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shown after opening a password-reset link (web): choose a new password.
class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog();

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  String? _problem;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final NotebookController controller = context.read<NotebookController>();
    if (_password.text.length < 6) {
      setState(() => _problem = 'Use at least 6 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _problem = "The passwords don't match.");
      return;
    }
    final bool ok = await controller.completePasswordRecovery(_password.text);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Use it to sign in on your other devices.'),
        ),
      );
    } else {
      setState(() => _problem = controller.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    return AlertDialog(
      icon: const Icon(Icons.lock_reset),
      title: const Text('Choose a new password'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Repeat password'),
              onSubmitted: (_) => _save(),
            ),
            if (_problem != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _problem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: controller.isBusy
              ? null
              : () {
                  controller.dismissPasswordRecovery();
                  Navigator.of(context).pop();
                },
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: controller.isBusy ? null : _save,
          child: const Text('Save password'),
        ),
      ],
    );
  }
}
