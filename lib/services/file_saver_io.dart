import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Native implementation: write a temp file, then share it.
Future<void> saveOrShareFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) async {
  final Directory dir = await getTemporaryDirectory();
  final File file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles(
    <XFile>[XFile(file.path, mimeType: mimeType)],
    subject: subject,
  );
}
