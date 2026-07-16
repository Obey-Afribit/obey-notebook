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
    if (imagePaths.isEmpty) {
      await Share.share(content, subject: title);
      return;
    }

    final List<XFile> files =
        imagePaths.map((String path) => XFile(path)).toList(growable: false);
    await Share.shareXFiles(files, text: content, subject: title);
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
