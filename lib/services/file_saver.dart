import 'dart:typed_data';

// Conditional export: on web (no dart:io) the web implementation is used;
// on native platforms the dart:io implementation is used.
import 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart' as impl;

/// Saves [bytes] as a file and hands it to the platform share/download flow.
/// On native platforms this writes a temp file and opens the share sheet; on
/// web it shares the bytes directly (Web Share API or download fallback).
Future<void> saveOrShareFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) {
  return impl.saveOrShareFile(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
    subject: subject,
  );
}
