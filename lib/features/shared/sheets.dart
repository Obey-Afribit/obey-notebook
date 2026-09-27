import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/folder_item.dart';
import '../../core/theme/note_colors.dart';
import '../../state/notebook_controller.dart';

/// Result of the colour picker. `colorId == null` means "no colour".
class ColorChoice {
  const ColorChoice(this.colorId);
  final String? colorId;
}

Future<ColorChoice?> showNoteColorPicker(
  BuildContext context, {
  String? current,
}) {
  return showModalBottomSheet<ColorChoice>(
    context: context,
    builder: (BuildContext sheetContext) {
      final Brightness brightness = Theme.of(sheetContext).brightness;
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Note colour',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _ColorDot(
                    color: scheme.surface,
                    selected: current == null,
                    tooltip: 'Default',
                    borderColor: scheme.outline,
                    icon: Icons.format_color_reset_outlined,
                    onTap: () =>
                        Navigator.of(sheetContext).pop(const ColorChoice(null)),
                  ),
                  for (final NoteColor color in NoteColors.all)
                    _ColorDot(
                      color: color.resolve(brightness),
                      selected: current == color.id,
                      tooltip: color.name,
                      borderColor: scheme.outlineVariant,
                      onTap: () =>
                          Navigator.of(sheetContext).pop(ColorChoice(color.id)),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.borderColor,
    required this.onTap,
    this.icon,
  });

  final Color color;
  final bool selected;
  final String tooltip;
  final Color borderColor;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.primary : borderColor,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 20, color: scheme.onSurface)
              : (icon == null
                  ? null
                  : Icon(icon, size: 20, color: scheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}

/// Folder chooser (as a tree), with a "New folder" shortcut. Returns the
/// chosen folder id.
Future<String?> showFolderPicker(
  BuildContext context,
  NotebookController controller, {
  String? currentFolderId,
  String title = 'Move to folder',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      final List<Widget> tiles = <Widget>[];
      void addLevel(String? parentId, int depth) {
        for (final FolderItem folder in controller.childFolders(parentId)) {
          final bool current = folder.id == currentFolderId;
          tiles.add(
            ListTile(
              contentPadding: EdgeInsets.only(left: 20.0 + depth * 20, right: 20),
              leading: Icon(
                controller.isFolderLocked(folder.id)
                    ? Icons.lock_outline
                    : Icons.folder_outlined,
              ),
              title: Text(folder.name),
              trailing: current ? const Icon(Icons.check) : null,
              selected: current,
              onTap: () => Navigator.of(sheetContext).pop(folder.id),
            ),
          );
          addLevel(folder.id, depth + 1);
        }
      }

      addLevel(null, 0);

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title,
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              Flexible(child: ListView(shrinkWrap: true, children: tiles)),
              const Divider(),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('New folder'),
                onTap: () async {
                  final String? name = await showNameDialog(
                    sheetContext,
                    title: 'New folder',
                    label: 'Folder name',
                  );
                  if (name == null || !sheetContext.mounted) {
                    return;
                  }
                  final FolderItem folder =
                      await controller.createFolder(name: name);
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop(folder.id);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// Quick reminder presets plus a custom date and time.
Future<DateTime?> showReminderPicker(
  BuildContext context, {
  DateTime? current,
}) async {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<(String, String, DateTime)> presets = <(String, String, DateTime)>[
    if (now.hour < 17)
      ('Later today', '18:00', today.add(const Duration(hours: 18))),
    (
      'Tomorrow morning',
      'Tomorrow 09:00',
      today.add(const Duration(days: 1, hours: 9)),
    ),
    (
      'Next week',
      '${DateFormat.E().format(_nextMonday(today))} 09:00',
      _nextMonday(today).add(const Duration(hours: 9)),
    ),
  ];

  final Object? picked = await showModalBottomSheet<Object>(
    context: context,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Remind me',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final (String label, String detail, DateTime at) in presets)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const Icon(Icons.schedule_outlined),
                title: Text(label),
                trailing: Text(detail),
                onTap: () => Navigator.of(sheetContext).pop(at),
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('Pick date and time'),
              onTap: () => Navigator.of(sheetContext).pop('custom'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (picked is DateTime) {
    return picked;
  }
  if (picked != 'custom' || !context.mounted) {
    return null;
  }

  final DateTime initial = current?.toLocal() ?? now.add(const Duration(hours: 1));
  final DateTime? date = await showDatePicker(
    context: context,
    firstDate: today,
    lastDate: DateTime(now.year + 5),
    initialDate: initial.isBefore(today) ? today : initial,
  );
  if (date == null || !context.mounted) {
    return null;
  }
  final TimeOfDay? time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) {
    return null;
  }
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

DateTime _nextMonday(DateTime today) {
  final int daysAhead = (DateTime.monday - today.weekday + 7) % 7;
  return today.add(Duration(days: daysAhead == 0 ? 7 : daysAhead));
}

/// Edits a note's tags. Returns the new list, or null if cancelled.
Future<List<String>?> showTagEditor(
  BuildContext context, {
  required List<String> current,
  required List<String> suggestions,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _TagEditorDialog(initial: current, suggestions: suggestions),
  );
}

class _TagEditorDialog extends StatefulWidget {
  const _TagEditorDialog({required this.initial, required this.suggestions});

  final List<String> initial;
  final List<String> suggestions;

  @override
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final List<String> _tags = <String>[...widget.initial];
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final String tag = NotebookController.normalizeTag(raw);
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
    }
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> unused = widget.suggestions
        .where((String s) => !_tags.contains(s))
        .take(12)
        .toList();

    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _input,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Add a tag and press Enter',
                prefixIcon: const Icon(Icons.tag),
                suffixIcon: IconButton(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add),
                  onPressed: () => _add(_input.text),
                ),
              ),
              onSubmitted: _add,
            ),
            const SizedBox(height: 14),
            if (_tags.isEmpty)
              Text(
                'No tags yet.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String tag in _tags)
                    InputChip(
                      label: Text('#$tag'),
                      onDeleted: () => setState(() => _tags.remove(tag)),
                    ),
                ],
              ),
            if (unused.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('Your tags', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String tag in unused)
                    ActionChip(
                      label: Text('#$tag'),
                      onPressed: () => _add(tag),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_input.text.trim().isNotEmpty) {
              _add(_input.text);
            }
            Navigator.of(context).pop(_tags);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Single-field text prompt (folder names and the like).
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _NameDialog(
      title: title,
      label: label,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _input =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _input.text.trim();
    if (value.isNotEmpty) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _input,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final ColorScheme scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Full-screen, zoomable image viewer.
Future<void> showImageViewer(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (BuildContext dialogContext) {
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.network(
                  url,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: IconButton.filledTonal(
                tooltip: 'Close',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      );
    },
  );
}
