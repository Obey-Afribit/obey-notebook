import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/note_item.dart';
import '../../state/notebook_controller.dart';

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

  Timer? _autosaveTimer;
  bool _isListening = false;
  bool _initialized = false;
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
      _titleController.addListener(_onTextChanged);
      _bodyController.addListener(_onTextChanged);
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
    _titleController.removeListener(_onTextChanged);
    _bodyController.removeListener(_onTextChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
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

  Future<void> _toggleSpeech() async {
    final NotebookController controller = context.read<NotebookController>();

    if (_isListening) {
      await controller.stopSpeechCapture();
      setState(() {
        _isListening = false;
      });
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

    setState(() {
      _isListening = true;
    });
  }

  String _mergeSpeechText(String current, String incoming) {
    final String base = current.trim();
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
        action: SnackBarAction(
          label: 'OCR',
          onPressed: () => _runOcr(pickedPath),
        ),
      ),
    );
  }

  Future<void> _runOcr(String path) async {
    final NotebookController controller = context.read<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);
    if (note == null) {
      return;
    }

    try {
      await controller.appendOcrTextToNote(note: note, imagePath: path);
      final NoteItem? refreshed = controller.getNoteById(widget.noteId);
      if (refreshed != null) {
        _bodyController.text = refreshed.body;
      }
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR unavailable: $error')),
      );
    }
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
        note: note, reminderAt: reminderAt.toUtc());
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
        await controller.exportNoteAsTxt(note);
        break;
      case 'export_pdf':
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
                    DateFormat('d MMM y HH:mm:ss').format(
                      version.updatedAt.toLocal(),
                    ),
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

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final NoteItem? note = controller.getNoteById(widget.noteId);

    if (!_initialized || note == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final String created =
        DateFormat('EEE, d MMM y HH:mm').format(note.createdAt.toLocal());
    final String updated =
        DateFormat('EEE, d MMM y HH:mm').format(note.updatedAt.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Note'),
        actions: <Widget>[
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
                child:
                    Text(note.isArchived ? 'Unarchive note' : 'Archive note'),
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
          padding: const EdgeInsets.all(14),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Created: $created\nUpdated: $updated',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (note.isPinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Chip(label: Text('Pinned')),
                    ),
                  if (note.isArchived)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Chip(label: Text('Archived')),
                    ),
                  if (note.reminderAt != null)
                    Chip(
                      avatar: const Icon(Icons.alarm, size: 18),
                      label: Text(
                        DateFormat('d MMM y HH:mm')
                            .format(note.reminderAt!.toLocal()),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _bodyController,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    labelText: 'Write your note',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              if (note.imagePaths.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: note.imagePaths.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final String path = note.imagePaths[index];
                      return Container(
                        width: 200,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Image attached',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Text(
                                path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => _runOcr(path),
                                child: const Text('OCR'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
