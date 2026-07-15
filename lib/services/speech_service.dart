import 'package:speech_to_text/speech_to_text.dart';

class SpeechCaptureResult {
  const SpeechCaptureResult({
    required this.words,
    required this.isFinal,
  });

  final String words;
  final bool isFinal;
}

class SpeechService {
  final SpeechToText _speechToText = SpeechToText();
  String? _localeId;

  bool get isListening => _speechToText.isListening;

  Future<bool> initialize() async {
    final bool available = await _speechToText.initialize();
    if (!available) {
      return false;
    }

    try {
      final LocaleName? systemLocale = await _speechToText.systemLocale();
      _localeId = systemLocale?.localeId;
    } catch (_) {
      _localeId = null;
    }

    return true;
  }

  Future<void> startListening({
    required void Function(SpeechCaptureResult result) onResult,
  }) async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    await _speechToText.listen(
      onResult: (result) {
        onResult(
          SpeechCaptureResult(
            words: result.recognizedWords,
            isFinal: result.finalResult,
          ),
        );
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> stopListening() {
    return _speechToText.stop();
  }
}
