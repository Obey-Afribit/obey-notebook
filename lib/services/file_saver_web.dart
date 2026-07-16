import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Web implementation: share the bytes directly. share_plus uses the Web Share
/// API when files are supported, otherwise it triggers a download.
Future<void> saveOrShareFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) async {
  await Share.shareXFiles(
    <XFile>[XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
    fileNameOverrides: <String>[fileName],
    subject: subject,
  );
}
