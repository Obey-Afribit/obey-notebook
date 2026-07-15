/// Image text extraction (OCR).
///
/// The on-device ML Kit engine only ships for Android and iOS and would break
/// Windows/Web builds, so the base app uses this graceful stub. Real OCR is
/// wired back in behind a platform guard during the mobile phase; until then
/// [extractTextFromImagePath] simply yields no text and the caller no-ops.
class OcrService {
  bool get isSupported => false;

  Future<String> extractTextFromImagePath(String path) async => '';

  Future<void> dispose() async {}
}
