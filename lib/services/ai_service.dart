import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';

/// Claude-powered note assistant.
///
/// Calls the Anthropic Messages API over HTTP (there is no official Dart SDK).
/// All features are gated on [AppConfig.hasAi]; when no key is configured the
/// AI UI is hidden rather than broken.
///
/// Security note: the key is read from a --dart-define at build time. That is
/// fine for a personal build with the user's own key, but a published app
/// should proxy these calls through a backend (e.g. a Supabase Edge Function)
/// so the key is never shipped to clients. On web, direct calls also expose the
/// key to the browser.
class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _endpoint = 'https://api.anthropic.com/v1/messages';
  static const String _model = 'claude-opus-4-8';

  bool get isAvailable => AppConfig.hasAi;

  /// Condenses a note into a few bullet points.
  Future<String> summarize(String noteBody) {
    return _completeText(
      system:
          'You summarize notes. Reply with 2-4 concise bullet points capturing '
          'the key information. Use "- " for each bullet. No preamble.',
      userText: noteBody,
      maxTokens: 512,
    );
  }

  /// Suggests a handful of short topical tags for a note.
  Future<List<String>> suggestTags(String noteBody) async {
    final String raw = await _completeText(
      system:
          'You suggest tags for notes. Reply with 3-6 short lowercase tags, '
          'comma-separated, no hashes, no explanation.',
      userText: noteBody,
      maxTokens: 128,
    );
    return raw
        .split(RegExp(r'[,\n]'))
        .map((String t) => t.trim().replaceAll('#', '').toLowerCase())
        .where((String t) => t.isNotEmpty && t.length <= 30)
        .take(6)
        .toList(growable: false);
  }

  /// Cleans up raw dictated or rough text: punctuation, capitalization,
  /// paragraph breaks. Preserves meaning and wording.
  Future<String> cleanUp(String rawText) {
    return _completeText(
      system:
          'You clean up rough or dictated text. Fix capitalization, '
          'punctuation, and paragraph breaks. Preserve the meaning and the '
          "author's wording. Reply with only the cleaned text, no preamble.",
      userText: rawText,
      maxTokens: 2048,
    );
  }

  Future<String> _completeText({
    required String system,
    required String userText,
    required int maxTokens,
  }) async {
    if (!AppConfig.hasAi) {
      throw StateError('AI is not configured for this build.');
    }
    if (userText.trim().isEmpty) {
      return '';
    }

    final http.Response response = await _client.post(
      Uri.parse(_endpoint),
      headers: <String, String>{
        'content-type': 'application/json',
        'x-api-key': AppConfig.anthropicApiKey,
        'anthropic-version': '2023-06-01',
        // Allows direct calls from a browser (web build). See the security
        // note above before relying on this in a published web app.
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: jsonEncode(<String, dynamic>{
        'model': _model,
        'max_tokens': maxTokens,
        'system': system,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': userText},
        ],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI request failed (${response.statusCode}).');
    }

    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;

    if (body['stop_reason'] == 'refusal') {
      throw Exception('The assistant declined this request.');
    }

    final List<dynamic> content = body['content'] as List<dynamic>? ?? const [];
    final StringBuffer buffer = StringBuffer();
    for (final dynamic block in content) {
      if (block is Map && block['type'] == 'text') {
        buffer.write(block['text'] as String? ?? '');
      }
    }
    return buffer.toString().trim();
  }

  void dispose() {
    _client.close();
  }
}
