import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/markdown_tools.dart';
import '../shared/sheets.dart';

/// Typography for rendered notes, scaled by the editor text-size setting.
MarkdownStyleSheet noteStyleSheet(ThemeData theme, double scale) {
  final ColorScheme s = theme.colorScheme;
  final TextTheme t = theme.textTheme;
  final TextStyle body = (t.bodyLarge ?? const TextStyle()).copyWith(
    fontSize: 16 * scale,
    height: 1.65,
    color: s.onSurface,
  );
  const List<String> mono = <String>[
    'Cascadia Code',
    'Consolas',
    'Menlo',
    'Roboto Mono',
    'monospace',
  ];

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    h1: body.copyWith(fontSize: 27 * scale, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.4),
    h2: body.copyWith(fontSize: 22 * scale, fontWeight: FontWeight.w700, height: 1.35, letterSpacing: -0.2),
    h3: body.copyWith(fontSize: 18.5 * scale, fontWeight: FontWeight.w600, height: 1.4),
    h4: body.copyWith(fontSize: 17 * scale, fontWeight: FontWeight.w600),
    h5: body.copyWith(fontWeight: FontWeight.w600),
    h6: body.copyWith(fontWeight: FontWeight.w600, color: s.onSurfaceVariant),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 2),
    h2Padding: const EdgeInsets.only(top: 8, bottom: 2),
    h3Padding: const EdgeInsets.only(top: 6),
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    del: body.copyWith(
      decoration: TextDecoration.lineThrough,
      color: s.onSurfaceVariant,
    ),
    a: body.copyWith(
      color: s.primary,
      decoration: TextDecoration.underline,
      decorationColor: s.primary.withValues(alpha: 0.5),
    ),
    code: body.copyWith(
      fontFamily: mono.first,
      fontFamilyFallback: mono,
      fontSize: 14 * scale,
      backgroundColor: s.surfaceContainerHighest,
      color: s.onSurface,
    ),
    codeblockPadding: const EdgeInsets.all(14),
    codeblockDecoration: BoxDecoration(
      color: s.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    blockquote: body.copyWith(color: s.onSurfaceVariant),
    blockquotePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
    blockquoteDecoration: BoxDecoration(
      color: s.primary.withValues(alpha: 0.06),
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
      border: Border(left: BorderSide(color: s.primary, width: 3)),
    ),
    listBullet: body.copyWith(color: s.primary),
    listIndent: 26,
    blockSpacing: 12 * scale,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: s.outlineVariant, width: 1.2)),
    ),
    tableHead: body.copyWith(fontWeight: FontWeight.w700),
    tableBody: body,
    tableBorder: TableBorder.all(color: s.outlineVariant),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    tableHeadAlign: TextAlign.left,
    checkbox: body.copyWith(color: s.primary),
  );
}

/// Rendered note body.
///
/// Checklist boxes are tappable: [onToggleTask] receives the task's index in
/// document order, matching [MarkdownTools.toggleTask].
class NoteMarkdown extends StatelessWidget {
  const NoteMarkdown({
    super.key,
    required this.data,
    required this.scale,
    this.onToggleTask,
  });

  final String data;
  final double scale;
  final ValueChanged<int>? onToggleTask;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // The renderer calls checkboxBuilder once per task, in document order, each
    // time it parses. Counting modulo the total keeps indices right even when
    // it re-parses with this same builder (for example on a theme change).
    final int total = MarkdownTools.countTasks(data);
    int seen = 0;

    return SelectionArea(
      child: MarkdownBody(
        data: data,
        styleSheet: noteStyleSheet(theme, scale),
        softLineBreak: true,
        onTapLink: (String text, String? href, String title) {
          final Uri? uri = href == null ? null : Uri.tryParse(href);
          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto')) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        checkboxBuilder: (bool checked) {
          final int index = total == 0 ? 0 : seen++ % total;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 22 * scale,
              height: 22 * scale,
              child: Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                side: BorderSide(color: scheme.outline, width: 1.5),
                onChanged: onToggleTask == null ? null : (_) => onToggleTask!(index),
              ),
            ),
          );
        },
        imageBuilder: (Uri uri, String? title, String? alt) =>
            _NoteImage(url: uri.toString(), alt: alt),
      ),
    );
  }
}

class _NoteImage extends StatelessWidget {
  const _NoteImage({required this.url, this.alt});

  final String url;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (!url.startsWith('http')) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => showImageViewer(context, url),
        child: MouseRegion(
          cursor: SystemMouseCursors.zoomIn,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                semanticLabel: alt,
                loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? progress) {
                  if (progress == null) {
                    return child;
                  }
                  return Container(
                    height: 200,
                    color: scheme.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: scheme.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 6),
                      Text(
                        "Image couldn't load",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
