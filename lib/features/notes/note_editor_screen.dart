import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/note_item.dart';
import '../../state/notebook_controller.dart';

enum _ViewMode { edit, split, preview }

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with WidgetsBindingObserver {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final FocusNode _bodyFocusNode = FocusNode();

  Timer? _autosaveTimer;
  bool _isListening = false;
  bool _initialized = false;
  _ViewMode _viewMode = _ViewMode.edit;
  String _speechSessionBaseText = '';
  String _lastFinalSpeechChunk = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }

    final NotebookController controller = context.read<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    if (note != null) {
      _titleController.text = note.title;
      _bodyController.text = note.body;
      _titleController.addListener(_scheduleSave);
      _bodyController.addListener(_onBodyChanged);
      _initialized = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _titleController.removeListener(_scheduleSave);
    _bodyController.removeListener(_onBodyChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  void _onBodyChanged() {
    if (_viewMode == _ViewMode.split) {
      setState(() {}); // live-refresh the preview pane
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  Future<void> _saveNow() async {
    final NotebookController controller = context.read<NotebookController>();
    final NoteItem? existing = controller.getNoteById(widget.noteId);
    if (existing == null) {
      return;
    }

    final NoteItem updated = existing.copyWith(
      title: _titleController.text.trim().isEmpty
          ? 'Untitled note'
          : _titleController.text.trim(),
      body: _bodyController.text,
      updatedAt: DateTime.now().toUtc(),
      localOnly: true,
    );

    await controller.saveNote(updated);
  }

  // ---------------------------------------------------------------------------
  // Markdown formatting helpers
  // ---------------------------------------------------------------------------

  void _wrapSelection(String left, String right) {
    final String text = _bodyController.text;
    TextSelection sel = _bodyController.selection;
    if (!sel.isValid) {
      sel = TextSelection.collapsed(offset: text.length);
    }
    final String selected = sel.textInside(text);
    final String replacement = '$left$selected$right';
    final String newText = text.replaceRange(sel.start, sel.end, replacement);
    final int cursor = selected.isEmpty
        ? sel.start + left.length
        : sel.start + replacement.length;
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _bodyFocusNode.requestFocus();
  }

  void _prefixLine(String prefix) {
    final String text = _bodyController.text;
    TextSelection sel = _bodyController.selection;
    if (!sel.isValid) {
      sel = TextSelection.collapsed(offset: text.length);
    }
    final int lineStart =
        sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
    final String newText = text.replaceRange(lineStart, lineStart, prefix);
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + prefix.length),
    );
    _bodyFocusNode.requestFocus();
  }

  void _insertAtCursor(String snippet) {
    final String text = _bodyController.text;
    TextSelection sel = _bodyController.selection;
    if (!sel.isValid) {
      sel = TextSelection.collapsed(offset: text.length);
    }
    final String newText = text.replaceRange(sel.start, sel.end, snippet);
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + snippet.length),
    );
    _bodyFocusNode.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // Dictation, images, OCR
  // ---------------------------------------------------------------------------

  Future<void> _toggleSpeech() async {
    final NotebookController controller = context.read<NotebookController>();

    if (_isListening) {
      await controller.stopSpeechCapture();
      setState(() => _isListening = false);
      await _saveNow();
      return;
    }

    _speechSessionBaseText = _bodyController.text;
    _lastFinalSpeechChunk = '';

    try {
      await controller.startSpeechCapture(
        onResult: (result) {
          final String words = result.words.trim();
          if (words.isEmpty) {
            return;
          }
          if (result.isFinal) {
            if (_lastFinalSpeechChunk == words) {
              return;
            }
            _lastFinalSpeechChunk = words;
            _speechSessionBaseText =
                _mergeSpeechText(_speechSessionBaseText, words);
            _bodyController.text = _speechSessionBaseText;
          } else {
            _bodyController.text =
                _mergeSpeechText(_speechSessionBaseText, words);
          }
          _bodyController.selection = TextSelection.fromPosition(
            TextPosition(offset: _bodyController.text.length),
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speech capture unavailable: $error')),
      );
      return;
    }

    setState(() => _isListening = true);
  }

  String _mergeSpeechText(String current, String incoming) {
    final String base = current.trimRight();
    final String chunk = incoming.trim();
    if (base.isEmpty) {
      return chunk;
    }
    if (chunk.isEmpty) {
      return base;
    }
    return '$base $chunk';
  }

  Future<void> _pickImage() async {
    final NotebookController controller = context.read<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    if (note == null) {
      return;
    }

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    final String? pickedPath = result?.files.single.path;
    if (pickedPath == null) {
      return;
    }

    await controller.attachImageToNote(note: note, imagePath: pickedPath);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Image attached.'),
        action: controller.ocrSupported
            ? SnackBarAction(label: 'OCR', onPressed: () => _runOcr(pickedPath))
            : null,
      ),
    );
  }

  Future<void> _runOcr(String path) async {
    final NotebookController controller = context.read<NotebookController>();
    try {
      final String extracted = await controller.extractTextFromImage(path);
      if (extracted.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No text found (OCR runs on mobile builds).'),
            ),
          );
        }
        return;
      }
      _insertAtCursor('\n\n${extracted.trim()}\n');
      await _saveNow();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR unavailable: $error')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // AI assistance
  // ---------------------------------------------------------------------------

  Future<void> _runAi(String action) async {
    final NotebookController controller = context.read<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    if (note == null) {
      return;
    }
    await _saveNow();
    if (!mounted) {
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 30),
        content: Row(
          children: <Widget>[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Asking the assistant...'),
          ],
        ),
      ),
    );

    try {
      switch (action) {
        case 'summarize':
          final String summary =
              await controller.summarizeText(_bodyController.text);
          if (summary.isNotEmpty) {
            _insertAt(0, '## Summary\n$summary\n\n');
            await _saveNow();
          }
          break;
        case 'cleanup':
          final String cleaned =
              await controller.cleanUpText(_bodyController.text);
          if (cleaned.isNotEmpty) {
            _bodyController.text = cleaned;
            await _saveNow();
          }
          break;
        case 'tags':
          await controller.suggestAndAddTags(note);
          break;
      }
      messenger.hideCurrentSnackBar();
    } catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('AI unavailable: $error')),
      );
    }
  }

  void _insertAt(int index, String snippet) {
    final String text = _bodyController.text;
    final int safeIndex = index.clamp(0, text.length);
    final String newText = text.replaceRange(safeIndex, safeIndex, snippet);
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: safeIndex + snippet.length),
    );
  }

  Future<void> _setReminder() async {
    final NotebookController controller = context.read<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    if (note == null) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      initialDate: note.reminderAt?.toLocal() ?? now,
    );
    if (pickedDate == null || !mounted) {
      return;
    }

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(note.reminderAt?.toLocal() ?? now),
    );
    if (pickedTime == null) {
      return;
    }

    final DateTime reminderAt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    await controller.applyReminderToNote(
      note: note,
      reminderAt: reminderAt.toUtc(),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _shareNote() async {
    final NotebookController controller = context.read<NotebookController>();
    await _saveNow();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    if (note == null) {
      return;
    }
    await controller.shareNote(note);
  }

  Future<void> _moveToTrash() async {
    final NotebookController controller = context.read<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    if (note == null) {
      return;
    }
    await controller.moveToTrash(note);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleMoreAction(String action) async {
    final NotebookController controller = context.read<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    if (note == null) {
      return;
    }

    switch (action) {
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
      case 'history':
        await _showVersionHistory();
        break;
      case 'export_txt':
        await _saveNow();
        await controller.exportNoteAsTxt(note);
        break;
      case 'export_pdf':
        await _saveNow();
        await controller.exportNoteAsPdf(note);
        break;
      case 'delete_forever':
        await controller.permanentlyDeleteNote(note.id);
        if (mounted) {
          Navigator.of(context).pop();
        }
        break;
      default:
        break;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showVersionHistory() async {
    final NotebookController controller = context.read<NotebookController>();
    final List<NoteItem> versions = controller.getVersionHistory(widget.noteId);
    if (versions.isEmpty || !mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Version History'),
          content: SizedBox(
            width: 620,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: versions.length,
              itemBuilder: (BuildContext context, int index) {
                final NoteItem version = versions[index];
                return ListTile(
                  title: Text(
                    DateFormat('d MMM y HH:mm:ss')
                        .format(version.updatedAt.toLocal()),
                  ),
                  subtitle: Text(
                    version.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await controller.restoreVersion(
                        noteId: widget.noteId,
                        version: version,
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      final NoteItem? refreshed =
                          controller.getNoteById(widget.noteId);
                      if (refreshed != null) {
                        _titleController.text = refreshed.title;
                        _bodyController.text = refreshed.body;
                      }
                    },
                    child: const Text('Restore'),
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
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);

    if (!_initialized || note == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final String updated =
        DateFormat('EEE, d MMM y HH:mm').format(note.updatedAt.toLocal());

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth > 820;
        // Split view is only offered on wide layouts.
        final _ViewMode effectiveMode =
            (!wide && _viewMode == _ViewMode.split) ? _ViewMode.edit : _viewMode;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Edit Note'),
            actions: <Widget>[
              if (controller.aiAvailable)
                PopupMenuButton<String>(
                  tooltip: 'AI assist',
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onSelected: _runAi,
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'summarize',
                      child: Text('Summarize into note'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'cleanup',
                      child: Text('Clean up writing'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'tags',
                      child: Text('Suggest tags'),
                    ),
                  ],
                ),
              IconButton(
                tooltip: _isListening ? 'Stop dictation' : 'Speech to text',
                onPressed: controller.speechAvailable ? _toggleSpeech : null,
                icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
              ),
              IconButton(
                tooltip: 'Insert image',
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined),
              ),
              IconButton(
                tooltip: 'Set reminder',
                onPressed: _setReminder,
                icon: const Icon(Icons.alarm),
              ),
              IconButton(
                tooltip: 'Share note',
                onPressed: _shareNote,
                icon: const Icon(Icons.share),
              ),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: _handleMoreAction,
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'pin',
                    child: Text(note.isPinned ? 'Unpin note' : 'Pin note'),
                  ),
                  PopupMenuItem<String>(
                    value: 'archive',
                    child: Text(
                      note.isArchived ? 'Unarchive note' : 'Archive note',
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'history',
                    child: Text('Version history'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'export_txt',
                    child: Text('Export as TXT'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'export_pdf',
                    child: Text('Export as PDF'),
                  ),
                  if (note.isDeleted)
                    const PopupMenuItem<String>(
                      value: 'delete_forever',
                      child: Text('Delete forever'),
                    ),
                ],
              ),
              IconButton(
                tooltip: 'Move to trash',
                onPressed: _moveToTrash,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _titleController,
                    style: Theme.of(context).textTheme.titleLarge,
                    decoration: const InputDecoration(
                      hintText: 'Title',
                      border: InputBorder.none,
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Updated $updated',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (_isListening)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Chip(
                            avatar: Icon(Icons.mic, size: 16),
                            label: Text('Listening'),
                          ),
                        ),
                      if (note.reminderAt != null)
                        Chip(
                          avatar: const Icon(Icons.alarm, size: 16),
                          label: Text(
                            DateFormat('d MMM HH:mm')
                                .format(note.reminderAt!.toLocal()),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _EditorToolbar(
                    viewMode: effectiveMode,
                    showSplit: wide,
                    onViewModeChanged: (_ViewMode mode) =>
                        setState(() => _viewMode = mode),
                    onBold: () => _wrapSelection('**', '**'),
                    onItalic: () => _wrapSelection('*', '*'),
                    onStrike: () => _wrapSelection('~~', '~~'),
                    onH1: () => _prefixLine('# '),
                    onH2: () => _prefixLine('## '),
                    onBullet: () => _prefixLine('- '),
                    onChecklist: () => _prefixLine('- [ ] '),
                    onQuote: () => _prefixLine('> '),
                    onCode: () => _wrapSelection('`', '`'),
                    onLink: () => _insertAtCursor('[title](https://)'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _buildEditorBody(effectiveMode),
                  ),
                  if (note.imagePaths.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.attach_file, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${note.imagePaths.length} attachment'
                          '${note.imagePaths.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditorBody(_ViewMode mode) {
    switch (mode) {
      case _ViewMode.edit:
        return _buildSourceField();
      case _ViewMode.preview:
        return _buildPreview();
      case _ViewMode.split:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: _buildSourceField()),
            const SizedBox(width: 10),
            Expanded(child: _buildPreview()),
          ],
        );
    }
  }

  Widget _buildSourceField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: 0.5,
              ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _bodyController,
        focusNode: _bodyFocusNode,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          hintText: 'Write in Markdown...',
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final String data = _bodyController.text.trim();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: data.isEmpty
          ? Center(
              child: Text(
                'Nothing to preview yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : Markdown(
              data: data,
              selectable: true,
              padding: EdgeInsets.zero,
            ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.viewMode,
    required this.showSplit,
    required this.onViewModeChanged,
    required this.onBold,
    required this.onItalic,
    required this.onStrike,
    required this.onH1,
    required this.onH2,
    required this.onBullet,
    required this.onChecklist,
    required this.onQuote,
    required this.onCode,
    required this.onLink,
  });

  final _ViewMode viewMode;
  final bool showSplit;
  final ValueChanged<_ViewMode> onViewModeChanged;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onStrike;
  final VoidCallback onH1;
  final VoidCallback onH2;
  final VoidCallback onBullet;
  final VoidCallback onChecklist;
  final VoidCallback onQuote;
  final VoidCallback onCode;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final bool formattingEnabled = viewMode != _ViewMode.preview;

    return Row(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _btn(Icons.format_bold, 'Bold', formattingEnabled ? onBold : null),
                _btn(Icons.format_italic, 'Italic',
                    formattingEnabled ? onItalic : null),
                _btn(Icons.strikethrough_s, 'Strikethrough',
                    formattingEnabled ? onStrike : null),
                _btn(Icons.title, 'Heading 1', formattingEnabled ? onH1 : null),
                _btn(Icons.text_fields, 'Heading 2',
                    formattingEnabled ? onH2 : null),
                _btn(Icons.format_list_bulleted, 'Bullet list',
                    formattingEnabled ? onBullet : null),
                _btn(Icons.checklist, 'Checklist',
                    formattingEnabled ? onChecklist : null),
                _btn(Icons.format_quote, 'Quote',
                    formattingEnabled ? onQuote : null),
                _btn(Icons.code, 'Inline code', formattingEnabled ? onCode : null),
                _btn(Icons.link, 'Link', formattingEnabled ? onLink : null),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<_ViewMode>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: <ButtonSegment<_ViewMode>>[
            const ButtonSegment<_ViewMode>(
              value: _ViewMode.edit,
              icon: Icon(Icons.edit_outlined, size: 18),
            ),
            if (showSplit)
              const ButtonSegment<_ViewMode>(
                value: _ViewMode.split,
                icon: Icon(Icons.vertical_split_outlined, size: 18),
              ),
            const ButtonSegment<_ViewMode>(
              value: _ViewMode.preview,
              icon: Icon(Icons.visibility_outlined, size: 18),
            ),
          ],
          selected: <_ViewMode>{viewMode},
          onSelectionChanged: (Set<_ViewMode> selection) =>
              onViewModeChanged(selection.first),
        ),
      ],
    );
  }

  Widget _btn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }
}
