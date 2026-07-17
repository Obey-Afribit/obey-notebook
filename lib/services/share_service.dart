import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/models/folder_item.dart';
import '../core/models/note_item.dart';
import '../core/models/template_item.dart';
import 'file_saver.dart';

/// Sharing and export. Free of dart:io so it compiles on web; file writing is
/// delegated to the platform-specific [saveOrShareFile].
class ShareService {
  Future<void> shareNoteText({
    required String title,
    required String body,
  }) {
    return Share.share('$title\n\n$body', subject: title);
  }

  Future<void> shareNoteWithImages({
    required String title,
    required String body,
    required List<String> imagePaths,
  }) async {
    final String content = '$title\n\n$body';
    final List<XFile> files = _localImageFiles(imagePaths);
    if (files.isEmpty) {
      await Share.share(content, subject: title);
      return;
    }

    await Share.shareXFiles(files, text: content, subject: title);
  }

  /// Shares several notes at once (used by multi-select bulk actions). Bodies
  /// are concatenated with a divider; any local image attachments ride along.
  Future<void> shareNotes(List<NoteItem> notes) async {
    if (notes.isEmpty) {
      return;
    }
    if (notes.length == 1) {
      await shareNoteWithImages(
        title: notes.first.title,
        body: notes.first.body,
        imagePaths: notes.first.imagePaths,
      );
      return;
    }

    final String content = notes
        .map((NoteItem note) => '${note.title}\n\n${note.body}')
        .join('\n\n${'-' * 24}\n\n');
    final String subject = '${notes.length} notes';

    final List<String> allImagePaths = <String>[
      for (final NoteItem note in notes) ...note.imagePaths,
    ];
    final List<XFile> files = _localImageFiles(allImagePaths);
    if (files.isEmpty) {
      await Share.share(content, subject: subject);
      return;
    }
    await Share.shareXFiles(files, text: content, subject: subject);
  }

  /// Only on-device files can be attached to a share sheet; remote (http) image
  /// URLs are left in the text body instead of being wrapped as [XFile]s.
  List<XFile> _localImageFiles(List<String> imagePaths) {
    return imagePaths
        .where((String path) => !path.startsWith('http'))
        .map((String path) => XFile(path))
        .toList(growable: false);
  }

  Future<void> exportNoteAsTxt(NoteItem note) async {
    final Uint8List bytes =
        Uint8List.fromList(utf8.encode('${note.title}\n\n${note.body}'));
    await saveOrShareFile(
      bytes: bytes,
      fileName: '${_safeName(note.title)}.txt',
      mimeType: 'text/plain',
      subject: '${note.title} (TXT export)',
    );
  }

  Future<void> exportNoteAsPdf(NoteItem note) async {
    final pw.Document doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (pw.Context context) => <pw.Widget>[
          pw.Text(
            note.title,
            style: const pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(note.body),
        ],
      ),
    );

    final Uint8List bytes = await doc.save();
    await saveOrShareFile(
      bytes: bytes,
      fileName: '${_safeName(note.title)}.pdf',
      mimeType: 'application/pdf',
      subject: '${note.title} (PDF export)',
    );
  }

  Future<void> exportBackupJson({
    required List<NoteItem> notes,
    required List<FolderItem> folders,
    required List<TemplateItem> templates,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'notes':
          notes.map((NoteItem note) => note.toMap()).toList(growable: false),
      'folders': folders
          .map((FolderItem folder) => folder.toMap())
          .toList(growable: false),
      'templates': templates
          .map((TemplateItem template) => template.toMap())
          .toList(growable: false),
    };

    final Uint8List bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
    await saveOrShareFile(
      bytes: bytes,
      fileName:
          'universal_notebook_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      mimeType: 'application/json',
      subject: 'Universal Notebook data backup',
    );
  }

  String _safeName(String value) {
    final String sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp('_+'), '_');
    return sanitized.isEmpty ? 'note' : sanitized;
  }
}
