import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/list_continuation.dart';
import '../../core/markdown_tools.dart';
import '../../core/models/note_item.dart';
import '../../core/theme/note_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../services/camera_capture.dart';
import '../../state/notebook_controller.dart';
import '../shared/sheets.dart';
import '../shared/ui.dart';
import 'markdown_view.dart';

enum _Mode { edit, read, split }

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId, this.isNew = false});

  final String noteId;

  /// Created just now: opens in edit mode and is discarded if left empty.
  final bool isNew;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();
  final UndoHistoryController _undo = UndoHistoryController();
  final ImagePicker _picker = ImagePicker();

  late NotebookController _controller;
  Timer? _autosave;
  bool _initialized = false;
  bool _dirty = false;
  bool _saving = false;
  bool _applyingRemote = false;
  bool _listening = false;
  bool _uploading = false;
  String _speechBase = '';
  _Mode _mode = _Mode.edit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _controller = context.read<NotebookController>();
    final NoteItem? note = _controller.getNoteById(widget.noteId);
    if (note == null) {
      return;
    }
    _title.text = note.displayTitle;
    _body.text = note.body;
    _title.addListener(_onTextChanged);
    _body.addListener(_onTextChanged);

    final bool readByDefault =
        context.read<ThemeController>().openInReadingView;
    _mode = widget.isNew || note.isEmpty || !readByDefault
        ? _Mode.edit
        : _Mode.read;
    if (note.isDeleted) {
      _mode = _Mode.read;
    }
    if (widget.isNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          (note.body.isEmpty ? _titleFocus : _bodyFocus).requestFocus();
        }
      });
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _autosave?.cancel();
    if (_listening) {
      unawaited(_controller.stopSpeechCapture());
    }
    if (_initialized) {
      unawaited(_finalize());
    }
    _title.removeListener(_onTextChanged);
    _body.removeListener(_onTextChanged);
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _undo.dispose();
    super.dispose();
  }

  /// Saves pending edits and drops the note if it was created and left empty.
  Future<void> _finalize() async {
    if (_dirty) {
      await _saveNow();
    }
    if (widget.isNew) {
      await _controller.discardIfEmpty(widget.noteId);
    }
  }

  // ---------------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------------

  void _onTextChanged() {
    if (_applyingRemote) {
      return;
    }
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 700), _saveNow);
    if (_mode == _Mode.split && mounted) {
      setState(() {}); // live preview
    }
  }

  Future<void> _saveNow() async {
    _autosave?.cancel();
    if (!_dirty) {
      return;
    }
    final NoteItem? existing = _controller.getNoteById(widget.noteId);
    if (existing == null) {
      return;
    }
    final String title = _title.text;
    final String body = _body.text;
    _dirty = false;
    if (existing.displayTitle == title.trim() && existing.body == body) {
      return;
    }
    _saving = true;
    try {
      await _controller.saveNote(existing.copyWith(title: title, body: body));
    } finally {
      _saving = false;
    }
  }

  bool get _busyEditing =>
      _dirty || _saving || (_autosave?.isActive ?? false);

  bool _matchesEditor(NoteItem note) =>
      note.displayTitle == _title.text.trim() && note.body == _body.text;

  /// Picks up edits made on another device (or by an action such as removing
  /// an image) while this note is open. Never while typing or saving: until a
  /// save completes the controller may still hold the previous copy.
  void _adoptRemote(NoteItem seen) {
    if (_busyEditing || _matchesEditor(seen)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final NoteItem? note = _controller.getNoteById(widget.noteId);
      if (!mounted || note == null || _busyEditing || _matchesEditor(note)) {
        return;
      }
      _applyingRemote = true;
      if (note.displayTitle != _title.text.trim()) {
        _title.text = note.displayTitle;
      }
      if (note.body != _body.text) {
        final int offset = _body.selection.baseOffset.clamp(0, note.body.length);
        _body.value = TextEditingValue(
          text: note.body,
          selection: TextSelection.collapsed(offset: offset),
        );
      }
      _applyingRemote = false;
      setState(() {});
    });
  }

  void _setMode(_Mode mode) {
    if (mode == _mode) {
      return;
    }
    if (_mode != _Mode.read) {
      unawaited(_saveNow());
    }
    setState(() => _mode = mode);
    if (mode != _Mode.read) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bodyFocus.requestFocus());
    }
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  TextSelection _selection() {
    final TextSelection sel = _body.selection;
    return sel.isValid ? sel : TextSelection.collapsed(offset: _body.text.length);
  }

  void _wrap(String left, String right, {String placeholder = 'text'}) {
    final String text = _body.text;
    final TextSelection sel = _selection();
    final String inner = sel.textInside(text);
    final String replacement = '$left${inner.isEmpty ? placeholder : inner}$right';
    _body.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, replacement),
      selection: inner.isEmpty
          ? TextSelection(
              baseOffset: sel.start + left.length,
              extentOffset: sel.start + left.length + placeholder.length,
            )
          : TextSelection.collapsed(offset: sel.start + replacement.length),
    );
    _bodyFocus.requestFocus();
  }

  /// Adds [prefix] to the current line, replacing any existing heading or list
  /// marker; applying the same prefix again removes it.
  void _linePrefix(String prefix) {
    final String text = _body.text;
    final TextSelection sel = _selection();
    final int lineStart = sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
    int lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd == -1) {
      lineEnd = text.length;
    }
    final String line = text.substring(lineStart, lineEnd);
    final RegExp existing = RegExp(r'^(#{1,6}\s+|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+|>\s?)');
    final RegExpMatch? match = existing.firstMatch(line);
    final String current = match?.group(0) ?? '';
    final String stripped = line.substring(current.length);
    final bool same = current.trim() == prefix.trim() && current.isNotEmpty;
    final String next = same ? stripped : '$prefix$stripped';
    final int delta = next.length - line.length;

    _body.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, next),
      selection: TextSelection.collapsed(
        offset: (sel.end + delta).clamp(lineStart, lineStart + next.length),
      ),
    );
    _bodyFocus.requestFocus();
  }

  void _insert(String snippet) {
    final String text = _body.text;
    final TextSelection sel = _selection();
    _body.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, snippet),
      selection: TextSelection.collapsed(offset: sel.start + snippet.length),
    );
    _bodyFocus.requestFocus();
  }

  void _insertLink() {
    final TextSelection sel = _selection();
    final String label = sel.textInside(_body.text);
    const String url = 'https://';
    final String snippet = '[${label.isEmpty ? 'link text' : label}]($url)';
    final String text = _body.text;
    _body.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, snippet),
      selection: TextSelection.collapsed(offset: sel.start + snippet.length - 1),
    );
    _bodyFocus.requestFocus();
  }

  void _toggleTask(int index) {
    final String updated = MarkdownTools.toggleTask(_body.text, index);
    if (updated != _body.text) {
      _body.text = updated; // triggers autosave
      HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Note-level actions
  // ---------------------------------------------------------------------------

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  NoteItem? get _note => _controller.getNoteById(widget.noteId);

  Future<void> _pickColor(NoteItem note) async {
    final ColorChoice? choice = await showNoteColorPicker(context, current: note.colorId);
    if (choice != null) {
      await _saveNow();
      await _controller.setNoteColor(_note ?? note, choice.colorId);
    }
  }

  Future<void> _pickReminder(NoteItem note) async {
    final DateTime? at = await showReminderPicker(context, current: note.reminderAt);
    if (at == null) {
      return;
    }
    if (at.isBefore(DateTime.now())) {
      _snack('Pick a time in the future.');
      return;
    }
    await _saveNow();
    final bool allowed = await _controller.setReminder(_note ?? note, at);
    if (!allowed) {
      _snack('Reminder saved, but notifications are off. Allow them in your '
          'phone settings to get an alert.');
    } else {
      _snack('Reminder set for ${reminderLabel(at)}.');
    }
  }

  Future<void> _clearReminder(NoteItem note) async {
    await _saveNow();
    await _controller.clearReminder(_note ?? note);
  }

  Future<void> _editTags(NoteItem note) async {
    final List<String>? tags = await showTagEditor(
      context,
      current: note.tags,
      suggestions: _controller.tagCounts.map((MapEntry<String, int> e) => e.key).toList(),
    );
    if (tags != null) {
      await _saveNow();
      await _controller.setTags(_note ?? note, tags);
    }
  }

  Future<void> _moveFolder(NoteItem note) async {
    final String? folderId = await showFolderPicker(
      context,
      _controller,
      currentFolderId: note.folderId,
    );
    if (folderId != null && folderId != note.folderId) {
      await _saveNow();
      await _controller.moveNoteToFolder(_note ?? note, folderId);
    }
  }

  Future<void> _share() async {
    await _saveNow();
    final NoteItem? note = _note;
    if (note != null) {
      await _controller.shareNote(note);
    }
  }

  Future<void> _moveToTrash(NoteItem note) async {
    await _saveNow();
    await _controller.moveToTrash(_note ?? note);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Note moved to trash.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              final NoteItem? trashed = _controller.getNoteById(note.id);
              if (trashed != null) {
                _controller.restoreFromTrash(trashed);
              }
            },
          ),
        ),
      );
    }
  }

  Future<void> _onMenu(String action, NoteItem note) async {
    switch (action) {
      case 'image':
        await _addImage();
        break;
      case 'dictate':
        await _toggleDictation();
        break;
      case 'tags':
        await _editTags(note);
        break;
      case 'move':
        await _moveFolder(note);
        break;
      case 'share':
        await _share();
        break;
      case 'template':
        await _saveNow();
        final NoteItem current = _note ?? note;
        await _controller.saveCustomTemplate(
          title: current.displayTitle.isEmpty ? 'My template' : current.displayTitle,
          body: current.body,
        );
        _snack('Saved as a template.');
        break;
      case 'history':
        await _showHistory();
        break;
      case 'txt':
        await _saveNow();
        await _controller.exportNoteAsTxt(_note ?? note);
        break;
      case 'pdf':
        await _saveNow();
        await _controller.exportNoteAsPdf(_note ?? note);
        break;
      case 'archive':
        await _saveNow();
        if (note.isArchived) {
          await _controller.unarchiveNote(_note ?? note);
          _snack('Note restored from the archive.');
        } else {
          await _controller.archiveNote(_note ?? note);
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
        break;
      case 'trash':
        await _moveToTrash(note);
        break;
      case 'ai_summary':
      case 'ai_cleanup':
      case 'ai_tags':
        await _runAi(action, note);
        break;
    }
  }

  Future<void> _runAi(String action, NoteItem note) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await _saveNow();
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 30),
        content: Text('Asking the assistant...'),
      ),
    );
    try {
      switch (action) {
        case 'ai_summary':
          final String summary = await _controller.summarizeText(_body.text);
          if (summary.isNotEmpty) {
            _body.text = '## Summary\n\n$summary\n\n${_body.text}';
          }
          break;
        case 'ai_cleanup':
          final String cleaned = await _controller.cleanUpText(_body.text);
          if (cleaned.isNotEmpty) {
            _body.text = cleaned;
          }
          break;
        case 'ai_tags':
          await _controller.suggestAndAddTags(_note ?? note);
          break;
      }
      messenger.hideCurrentSnackBar();
    } catch (_) {
      messenger.hideCurrentSnackBar();
      _snack("The assistant isn't available right now.");
    }
  }

  Future<void> _showHistory() async {
    await _saveNow();
    final List<NoteItem> versions = _controller.getVersionHistory(widget.noteId);
    if (!mounted) {
      return;
    }
    if (versions.length < 2) {
      _snack('No earlier versions yet. Versions are kept as you edit over time.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Version history',
                      style: Theme.of(sheetContext).textTheme.titleMedium),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: versions.length,
                    itemBuilder: (BuildContext context, int index) {
                      final NoteItem version = versions[index];
                      final bool current = index == 0;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                        title: Text(
                          DateFormat('EEE d MMM y, HH:mm').format(version.updatedAt.toLocal()),
                        ),
                        subtitle: Text(
                          MarkdownTools.previewText(version.body),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: current
                            ? const Chip(label: Text('Current'))
                            : TextButton(
                                onPressed: () async {
                                  await _controller.restoreVersion(
                                    noteId: widget.noteId,
                                    version: version,
                                  );
                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                  _snack('Version restored.');
                                },
                                child: const Text('Restore'),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Images and dictation
  // ---------------------------------------------------------------------------

  Future<void> _addImage() async {
    if (!_controller.imagesSupported) {
      _snack('Sign in to cloud sync to add images to your notes.');
      return;
    }
    final bool cameraSupported = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (cameraSupported)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
                ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose an image'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) {
      return;
    }

    Uint8List? bytes;
    String extension = 'jpg';
    if (source == ImageSource.camera && kIsWeb) {
      bytes = await captureFromWebcam(context);
    } else {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 82,
      );
      if (picked != null) {
        bytes = await picked.readAsBytes();
        final int dot = picked.name.lastIndexOf('.');
        if (dot != -1 && dot < picked.name.length - 1) {
          extension = picked.name.substring(dot + 1);
        }
      }
    }
    if (bytes == null || !mounted) {
      return;
    }

    setState(() => _uploading = true);
    try {
      final String url = await _controller.uploadNoteImage(
        noteId: widget.noteId,
        bytes: bytes,
        fileExtension: extension,
      );
      final String snippet = '\n\n![image]($url)\n\n';
      if (_mode == _Mode.read) {
        _body.text = '${_body.text.trimRight()}$snippet';
      } else {
        _insert(snippet);
      }
      await _saveNow();
      final NoteItem? note = _note;
      if (note != null) {
        await _controller.attachImageToNote(note: note, imagePath: url);
      }
    } catch (_) {
      _snack("The image couldn't be uploaded. Check your connection and try again.");
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _removeImage(NoteItem note, String url) async {
    if (!await confirmAction(
      context,
      title: 'Remove image?',
      message: 'It will be removed from this note and deleted from storage.',
      confirmLabel: 'Remove',
      destructive: true,
    )) {
      return;
    }
    await _saveNow();
    await _controller.removeImageFromNote(note: _note ?? note, imagePath: url);
  }

  Future<void> _toggleDictation() async {
    if (_listening) {
      await _controller.stopSpeechCapture();
      setState(() => _listening = false);
      await _saveNow();
      return;
    }
    if (_mode == _Mode.read) {
      _setMode(_Mode.edit);
    }
    _speechBase = _body.text;
    try {
      await _controller.startSpeechCapture(
        onResult: (result) {
          final String words = result.words.trim();
          if (words.isEmpty) {
            return;
          }
          final String base = _speechBase.trimRight();
          final String merged = base.isEmpty ? words : '$base $words';
          _body.value = TextEditingValue(
            text: merged,
            selection: TextSelection.collapsed(offset: merged.length),
          );
          if (result.isFinal) {
            _speechBase = merged;
          }
        },
      );
      setState(() => _listening = true);
    } catch (error) {
      _snack(error is StateError
          ? error.message
          : 'Dictation is unavailable on this device.');
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeController themeController = context.watch<ThemeController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    final ThemeData theme = Theme.of(context);

    if (note == null || !_initialized) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.note_alt_outlined,
          title: 'Note not found',
          message: 'It may have been deleted on another device.',
        ),
      );
    }
    _adoptRemote(note);

    final Color background =
        NoteColors.backgroundFor(note.colorId, theme.brightness) ??
            theme.colorScheme.surface;
    final double scale = themeController.editorTextSize.scale;
    final bool readOnly = note.isDeleted;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= Breakpoints.split;
        final bool desktop = constraints.maxWidth >= Breakpoints.sidebar;
        _Mode mode = _mode;
        if (readOnly) {
          mode = _Mode.read;
        } else if (!wide && mode == _Mode.split) {
          mode = _Mode.edit;
        }
        final bool editing = mode != _Mode.read;

        final Widget toolbar = _Toolbar(
          undo: _undo,
          onHeading1: () => _linePrefix('# '),
          onHeading2: () => _linePrefix('## '),
          onBold: () => _wrap('**', '**'),
          onItalic: () => _wrap('*', '*'),
          onStrike: () => _wrap('~~', '~~'),
          onBullet: () => _linePrefix('- '),
          onNumbered: () => _linePrefix('1. '),
          onChecklist: () => _linePrefix('- [ ] '),
          onQuote: () => _linePrefix('> '),
          onCode: () => _wrap('`', '`', placeholder: 'code'),
          onLink: _insertLink,
          onDivider: () => _insert('\n\n---\n\n'),
          onImage: _addImage,
          onDictate: controller.speechSupported ? _toggleDictation : null,
          listening: _listening,
        );

        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            if (editing) ...<ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _wrap('**', '**'),
              const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _wrap('*', '*'),
              const SingleActivator(LogicalKeyboardKey.keyK, control: true): _insertLink,
            },
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
              _dirty = true;
              _saveNow();
              _snack('Saved.');
            },
            const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
                _setMode(_mode == _Mode.read ? _Mode.edit : _Mode.read),
            const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
          },
          child: Scaffold(
            backgroundColor: background,
            appBar: AppBar(
              backgroundColor: background,
              bottom: _uploading
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(3),
                      child: LinearProgressIndicator(minHeight: 3),
                    )
                  : null,
              actions: readOnly
                  ? _trashActions(note)
                  : _actions(note, controller, wide: wide, desktop: desktop, mode: mode),
            ),
            floatingActionButton: !editing && !readOnly
                ? FloatingActionButton(
                    tooltip: 'Edit (Ctrl+E)',
                    onPressed: () => _setMode(_Mode.edit),
                    child: const Icon(Icons.edit_outlined),
                  )
                : null,
            body: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (readOnly) _TrashNotice(note: note, controller: controller),
                  if (editing && desktop) toolbar,
                  Expanded(child: _content(note, controller, mode, scale, readOnly)),
                  if (editing && !desktop) toolbar,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _trashActions(NoteItem note) {
    return <Widget>[
      TextButton.icon(
        onPressed: () async {
          await _controller.restoreFromTrash(note);
          _snack('Note restored.');
        },
        icon: const Icon(Icons.restore_from_trash_outlined),
        label: const Text('Restore'),
      ),
      IconButton(
        tooltip: 'Delete forever',
        onPressed: () async {
          if (await confirmAction(
            context,
            title: 'Delete forever?',
            message: 'This note and its images will be permanently deleted.',
            confirmLabel: 'Delete',
            destructive: true,
          )) {
            await _controller.permanentlyDeleteNote(note.id);
            if (mounted) {
              Navigator.of(context).pop();
            }
          }
        },
        icon: const Icon(Icons.delete_forever_outlined),
      ),
      const SizedBox(width: 4),
    ];
  }

  List<Widget> _actions(
    NoteItem note,
    NotebookController controller, {
    required bool wide,
    required bool desktop,
    required _Mode mode,
  }) {
    return <Widget>[
      if (wide)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SegmentedButton<_Mode>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const <ButtonSegment<_Mode>>[
              ButtonSegment<_Mode>(
                value: _Mode.edit,
                icon: Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit',
              ),
              ButtonSegment<_Mode>(
                value: _Mode.split,
                icon: Icon(Icons.vertical_split_outlined, size: 18),
                tooltip: 'Side by side',
              ),
              ButtonSegment<_Mode>(
                value: _Mode.read,
                icon: Icon(Icons.chrome_reader_mode_outlined, size: 18),
                tooltip: 'Reading view',
              ),
            ],
            selected: <_Mode>{mode},
            onSelectionChanged: (Set<_Mode> s) => _setMode(s.first),
          ),
        )
      else if (mode != _Mode.read)
        IconButton(
          tooltip: 'Reading view',
          onPressed: () => _setMode(_Mode.read),
          icon: const Icon(Icons.chrome_reader_mode_outlined),
        ),
      IconButton(
        tooltip: note.isPinned ? 'Unpin' : 'Pin',
        onPressed: () async {
          await _saveNow();
          await controller.togglePin(_note ?? note);
        },
        icon: Icon(note.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
      ),
      IconButton(
        tooltip: 'Reminder',
        onPressed: () => _pickReminder(note),
        icon: Icon(note.reminderAt == null ? Icons.alarm_add_outlined : Icons.alarm_on),
      ),
      IconButton(
        tooltip: 'Colour',
        onPressed: () => _pickColor(note),
        icon: const Icon(Icons.palette_outlined),
      ),
      if (desktop)
        IconButton(
          tooltip: 'Share',
          onPressed: _share,
          icon: const Icon(Icons.ios_share),
        ),
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (String value) => _onMenu(value, note),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          _item('image', Icons.add_photo_alternate_outlined, 'Add image'),
          if (controller.speechSupported)
            _item('dictate', _listening ? Icons.mic_off_outlined : Icons.mic_none,
                _listening ? 'Stop dictation' : 'Dictate'),
          _item('tags', Icons.tag, 'Tags'),
          _item('move', Icons.drive_file_move_outline, 'Move to folder'),
          if (!desktop) _item('share', Icons.ios_share, 'Share'),
          if (controller.aiAvailable) ...<PopupMenuEntry<String>>[
            const PopupMenuDivider(),
            _item('ai_summary', Icons.auto_awesome_outlined, 'Summarise'),
            _item('ai_cleanup', Icons.spellcheck, 'Clean up writing'),
            _item('ai_tags', Icons.sell_outlined, 'Suggest tags'),
          ],
          const PopupMenuDivider(),
          _item('template', Icons.bookmark_add_outlined, 'Save as template'),
          _item('history', Icons.history, 'Version history'),
          _item('txt', Icons.description_outlined, 'Export as text'),
          _item('pdf', Icons.picture_as_pdf_outlined, 'Export as PDF'),
          const PopupMenuDivider(),
          _item('archive', note.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              note.isArchived ? 'Unarchive' : 'Archive'),
          _item('trash', Icons.delete_outline, 'Move to trash'),
        ],
      ),
      const SizedBox(width: 4),
    ];
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: ListTile(leading: Icon(icon), title: Text(label)),
    );
  }

  Widget _content(
    NoteItem note,
    NotebookController controller,
    _Mode mode,
    double scale,
    bool readOnly,
  ) {
    switch (mode) {
      case _Mode.read:
        return _ReadingPane(
          note: note,
          controller: controller,
          title: _title.text,
          body: _body.text,
          scale: scale,
          onToggleTask: readOnly ? null : _toggleTask,
          onEditTitle: readOnly ? null : () => _setMode(_Mode.edit),
          meta: _MetaBar(
            note: note,
            controller: controller,
            body: _body.text,
            onFolder: readOnly ? null : () => _moveFolder(note),
            onReminder: readOnly ? null : () => _pickReminder(note),
            onClearReminder: readOnly ? null : () => _clearReminder(note),
            onTags: readOnly ? null : () => _editTags(note),
          ),
        );
      case _Mode.edit:
        return _editPane(note, controller, scale);
      case _Mode.split:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: _editPane(note, controller, scale)),
            const VerticalDivider(width: 1),
            Expanded(
              child: _ReadingPane(
                note: note,
                controller: controller,
                title: _title.text,
                body: _body.text,
                scale: scale,
                onToggleTask: _toggleTask,
                compact: true,
              ),
            ),
          ],
        );
    }
  }

  Widget _editPane(NoteItem note, NotebookController controller, double scale) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<String> images = <String>{
      ...note.imagePaths,
      ...MarkdownTools.imageUrls(note.body),
    }.where((String u) => u.startsWith('http')).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _title,
                focusNode: _titleFocus,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _bodyFocus.requestFocus(),
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: 26 * scale),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
              _MetaBar(
                note: note,
                controller: controller,
                body: _body.text,
                onFolder: () => _moveFolder(note),
                onReminder: () => _pickReminder(note),
                onClearReminder: () => _clearReminder(note),
                onTags: () => _editTags(note),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TextField(
                  controller: _body,
                  focusNode: _bodyFocus,
                  undoController: _undo,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textAlignVertical: TextAlignVertical.top,
                  inputFormatters: <TextInputFormatter>[ListContinuationFormatter()],
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 16 * scale,
                    height: 1.6,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Start writing. Markdown works: # heading, - list, - [ ] task',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (BuildContext context, int index) => _Thumb(
                        url: images[index],
                        onOpen: () => showImageViewer(context, images[index]),
                        onRemove: () => _removeImage(note, images[index]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Pieces
// =============================================================================

class _ReadingPane extends StatelessWidget {
  const _ReadingPane({
    required this.note,
    required this.controller,
    required this.title,
    required this.body,
    required this.scale,
    this.onToggleTask,
    this.onEditTitle,
    this.meta,
    this.compact = false,
  });

  final NoteItem note;
  final NotebookController controller;
  final String title;
  final String body;
  final double scale;
  final ValueChanged<int>? onToggleTask;
  final VoidCallback? onEditTitle;
  final Widget? meta;

  /// Split view: body only, no title block.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!compact) ...<Widget>[
                  GestureDetector(
                    onTap: onEditTitle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        title.trim().isEmpty ? 'Untitled' : title.trim(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: 26 * scale,
                          color: title.trim().isEmpty ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                  ),
                  if (meta != null) meta!,
                  const SizedBox(height: 12),
                ] else
                  const SizedBox(height: 12),
                if (body.trim().isEmpty)
                  Text(
                    'Nothing here yet. Tap the pencil to start writing.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  )
                else
                  NoteMarkdown(data: body, scale: scale, onToggleTask: onToggleTask),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Folder, reminder, tags, edited time and word count, as one quiet row.
class _MetaBar extends StatelessWidget {
  const _MetaBar({
    required this.note,
    required this.controller,
    required this.body,
    this.onFolder,
    this.onReminder,
    this.onClearReminder,
    this.onTags,
  });

  final NoteItem note;
  final NotebookController controller;
  final String body;
  final VoidCallback? onFolder;
  final VoidCallback? onReminder;
  final VoidCallback? onClearReminder;
  final VoidCallback? onTags;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int words = MarkdownTools.wordCount(body);
    final int minutes = MarkdownTools.readingMinutes(words);
    final String folder = controller.folderById(note.folderId)?.name ?? 'Inbox';
    final bool overdue = note.reminderAt != null && note.reminderAt!.isBefore(DateTime.now());

    final ChipThemeData chipTheme = ChipTheme.of(context).copyWith(
      backgroundColor: scheme.onSurface.withValues(alpha: 0.05),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      labelStyle: theme.textTheme.labelMedium,
    );

    return ChipTheme(
      data: chipTheme,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ActionChip(
            avatar: const Icon(Icons.folder_outlined, size: 16),
            label: Text(folder),
            onPressed: onFolder,
          ),
          if (note.reminderAt != null)
            InputChip(
              avatar: Icon(overdue ? Icons.alarm_off : Icons.alarm, size: 16,
                  color: overdue ? scheme.error : null),
              label: Text(reminderLabel(note.reminderAt!)),
              onPressed: onReminder,
              onDeleted: onClearReminder,
              deleteButtonTooltipMessage: 'Remove reminder',
            ),
          for (final String tag in note.tags)
            ActionChip(label: Text('#$tag'), onPressed: onTags),
          if (onTags != null && note.tags.isEmpty)
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Tag'),
              onPressed: onTags,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Edited ${relativeTime(note.updatedAt).toLowerCase()}'
              '${words == 0 ? '' : '  |  $words word${words == 1 ? '' : 's'}, $minutes min read'}',
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashNotice extends StatelessWidget {
  const _TrashNotice({required this.note, required this.controller});

  final NoteItem note;
  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This note is in the trash. Restore it to make changes.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.onOpen, required this.onRemove});

  final String url;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: onOpen,
            child: Image.network(
              url,
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 76,
                height: 76,
                color: scheme.surfaceContainerHigh,
                child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        Positioned(
          top: 3,
          right: 3,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.undo,
    required this.onHeading1,
    required this.onHeading2,
    required this.onBold,
    required this.onItalic,
    required this.onStrike,
    required this.onBullet,
    required this.onNumbered,
    required this.onChecklist,
    required this.onQuote,
    required this.onCode,
    required this.onLink,
    required this.onDivider,
    required this.onImage,
    required this.onDictate,
    required this.listening,
  });

  final UndoHistoryController undo;
  final VoidCallback onHeading1;
  final VoidCallback onHeading2;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onStrike;
  final VoidCallback onBullet;
  final VoidCallback onNumbered;
  final VoidCallback onChecklist;
  final VoidCallback onQuote;
  final VoidCallback onCode;
  final VoidCallback onLink;
  final VoidCallback onDivider;
  final VoidCallback onImage;
  final VoidCallback? onDictate;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    Widget button(IconData icon, String tip, VoidCallback? onTap, {bool active = false}) {
      return IconButton(
        tooltip: tip,
        onPressed: onTap,
        isSelected: active,
        visualDensity: VisualDensity.compact,
        color: active ? scheme.primary : null,
        icon: Icon(icon, size: 21),
      );
    }

    Widget gap() => Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: scheme.outlineVariant,
        );

    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: <Widget>[
            ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: undo,
              builder: (BuildContext context, UndoHistoryValue value, _) => Row(
                children: <Widget>[
                  button(Icons.undo, 'Undo', value.canUndo ? undo.undo : null),
                  button(Icons.redo, 'Redo', value.canRedo ? undo.redo : null),
                ],
              ),
            ),
            gap(),
            button(Icons.title, 'Heading', onHeading1),
            button(Icons.text_fields, 'Subheading', onHeading2),
            button(Icons.format_bold, 'Bold (Ctrl+B)', onBold),
            button(Icons.format_italic, 'Italic (Ctrl+I)', onItalic),
            button(Icons.strikethrough_s, 'Strikethrough', onStrike),
            gap(),
            button(Icons.checklist, 'Checklist', onChecklist),
            button(Icons.format_list_bulleted, 'Bulleted list', onBullet),
            button(Icons.format_list_numbered, 'Numbered list', onNumbered),
            button(Icons.format_quote_outlined, 'Quote', onQuote),
            button(Icons.code, 'Code', onCode),
            button(Icons.link, 'Link (Ctrl+K)', onLink),
            button(Icons.horizontal_rule, 'Divider', onDivider),
            gap(),
            button(Icons.add_photo_alternate_outlined, 'Add image', onImage),
            if (onDictate != null)
              button(listening ? Icons.mic : Icons.mic_none,
                  listening ? 'Stop dictation' : 'Dictate', onDictate, active: listening),
          ],
        ),
      ),
    );
  }
}
