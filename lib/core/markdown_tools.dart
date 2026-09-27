/// Pure helpers for working with note bodies (Markdown source).
///
/// Everything here is UI-free so it can be unit tested.
library;

/// A GFM task-list item: `- [ ]`, `* [x]`, `1. [ ]`, with optional indent.
final RegExp _taskLine = RegExp(r'^(\s*(?:[-*+]|\d+[.)])\s+)\[([ xX])\]');
final RegExp _fence = RegExp(r'^\s*(```|~~~)');
final RegExp _inlineImage = RegExp(r'!\[[^\]]*\]\(([^)\s]+)[^)]*\)');

class TaskProgress {
  const TaskProgress(this.done, this.total);

  final int done;
  final int total;

  bool get hasTasks => total > 0;
}

class MarkdownTools {
  const MarkdownTools._();

  /// Line ranges of task items, in document order, skipping fenced code blocks
  /// (the renderer does not draw checkboxes inside code, so neither do we).
  static List<_TaskHit> _tasks(String source) {
    final List<_TaskHit> hits = <_TaskHit>[];
    bool inFence = false;
    int offset = 0;
    for (final String line in source.split('\n')) {
      if (_fence.hasMatch(line)) {
        inFence = !inFence;
      } else if (!inFence) {
        final RegExpMatch? match = _taskLine.firstMatch(line);
        if (match != null) {
          final int markOffset = offset + match.group(1)!.length + 1;
          hits.add(_TaskHit(markOffset, match.group(2)! != ' '));
        }
      }
      offset += line.length + 1; // + the newline split() removed
    }
    return hits;
  }

  static int countTasks(String source) => _tasks(source).length;

  static TaskProgress taskProgress(String source) {
    final List<_TaskHit> hits = _tasks(source);
    return TaskProgress(hits.where((_TaskHit h) => h.checked).length, hits.length);
  }

  /// Flips the [index]-th task (0-based, document order). Returns the source
  /// unchanged if [index] is out of range.
  static String toggleTask(String source, int index) {
    final List<_TaskHit> hits = _tasks(source);
    if (index < 0 || index >= hits.length) {
      return source;
    }
    final _TaskHit hit = hits[index];
    final String replacement = hit.checked ? ' ' : 'x';
    return source.replaceRange(hit.markOffset, hit.markOffset + 1, replacement);
  }

  /// URLs of inline images, in order.
  static List<String> imageUrls(String source) => _inlineImage
      .allMatches(source)
      .map((RegExpMatch m) => m.group(1)!)
      .toList(growable: false);

  /// Removes every inline image that points at [url].
  static String removeImage(String source, String url) {
    final RegExp pattern =
        RegExp(r'!\[[^\]]*\]\(' + RegExp.escape(url) + r'[^)]*\)\n?');
    return source.replaceAll(pattern, '').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  /// A clean, one-glance text preview for note cards.
  static String previewText(String body) {
    return body
        .replaceAll(_inlineImage, '')
        .replaceAll(RegExp(r'^\s*(```|~~~).*$', multiLine: true), '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\|?\s*-{3,}.*$', multiLine: true), '')
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]*\)'),
          (Match m) => m.group(1)!,
        )
        .replaceAll(RegExp(r'[*_`~|]'), '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n')
        .trim();
  }

  static int wordCount(String body) {
    final String text = previewText(body);
    if (text.isEmpty) {
      return 0;
    }
    return RegExp(r"[\p{L}\p{N}'’]+", unicode: true).allMatches(text).length;
  }

  /// Minutes to read at roughly 220 words per minute, never less than 1.
  static int readingMinutes(int words) => words == 0 ? 0 : (words / 220).ceil();
}

class _TaskHit {
  const _TaskHit(this.markOffset, this.checked);

  /// Offset of the character inside the brackets (the space or the x).
  final int markOffset;
  final bool checked;
}
