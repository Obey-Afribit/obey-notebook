import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/models/folder_item.dart';
import '../core/models/note_item.dart';
import '../core/models/template_item.dart';

class ShareService {
  Future<void> shareNoteText({
    required String title,
    required String body,
  }) {
    final String content = '$title\n\n$body';
    return Share.share(content, subject: title);
  }

  Future<void> shareNoteWithImages({
    required String title,
    required String body,
    required List<String> imagePaths,
  }) async {
    final String content = '$title\n\n$body';
    final List<XFile> files = imagePaths
        .map((String path) => XFile(path))
        .where((XFile file) => File(file.path).existsSync())
        .toList(growable: false);

    if (files.isEmpty) {
      await Share.share(content, subject: title);
      return;
    }

    await Share.shareXFiles(files, text: content, subject: title);
  }

  Future<String> exportNoteAsTxt(NoteItem note) async {
    final Directory dir = await getTemporaryDirectory();
    final String fileName =
        '${_safeName(note.title)}_${DateTime.now().millisecondsSinceEpoch}.txt';
    final File file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString('${note.title}\n\n${note.body}');
    return file.path;
  }

  Future<String> exportNoteAsPdf(NoteItem note) async {
    final Directory dir = await getTemporaryDirectory();
    final String fileName =
        '${_safeName(note.title)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final File file = File('${dir.path}${Platform.pathSeparator}$fileName');

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

    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  Future<void> shareFilePath({
    required String filePath,
    String? text,
    String? subject,
  }) {
    return Share.shareXFiles(
      <XFile>[XFile(filePath)],
      text: text,
      subject: subject,
    );
  }

  Future<String> exportBackupJson({
    required List<NoteItem> notes,
    required List<FolderItem> folders,
    required List<TemplateItem> templates,
  }) async {
    final Directory dir = await getTemporaryDirectory();
    final String fileName =
        'universal_notebook_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final File file = File('${dir.path}${Platform.pathSeparator}$fileName');

    final Map<String, dynamic> payload = <String, dynamic>{
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'notes': notes.map((NoteItem note) => note.toMap()).toList(growable: false),
      'folders':
          folders.map((FolderItem folder) => folder.toMap()).toList(growable: false),
      'templates': templates
          .map((TemplateItem template) => template.toMap())
          .toList(growable: false),
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return file.path;
  }

  String _safeName(String value) {
    final String sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp('_+'), '_');
    return sanitized.isEmpty ? 'note' : sanitized;
  }
}
