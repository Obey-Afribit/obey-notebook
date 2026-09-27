import 'package:flutter/services.dart';

/// Continues Markdown lists when Enter is pressed.
///
/// * `- item` + Enter -> new line starting `- `
/// * `- [x] done` + Enter -> new line starting `- [ ] `
/// * `3. step` + Enter -> new line starting `4. `
/// * Enter on an empty item (just the marker) ends the list.
///
/// Only a single typed newline at a collapsed cursor is handled, so pasting
/// text is never altered.
class ListContinuationFormatter extends TextInputFormatter {
  static final RegExp _item =
      RegExp(r'^(\s*)([-*+]|\d{1,6}[.)])(\s+)(\[[ xX]\]\s+)?');
  static final RegExp _numbered = RegExp(r'^(\d+)([.)])$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final TextSelection sel = newValue.selection;
    if (!sel.isValid ||
        !sel.isCollapsed ||
        newValue.text.length != oldValue.text.length + 1 ||
        oldValue.selection.baseOffset != sel.baseOffset - 1) {
      return newValue;
    }
    final int cursor = sel.baseOffset;
    final String text = newValue.text;
    if (cursor <= 0 || text[cursor - 1] != '\n') {
      return newValue;
    }

    final int lineStart = cursor - 2 < 0 ? 0 : text.lastIndexOf('\n', cursor - 2) + 1;
    final String previous = text.substring(lineStart, cursor - 1);
    final RegExpMatch? match = _item.firstMatch(previous);
    if (match == null) {
      return newValue;
    }

    final String content = previous.substring(match.end);
    if (content.trim().isEmpty) {
      // Empty item: remove the marker line and the newline, ending the list.
      return TextEditingValue(
        text: text.replaceRange(lineStart, cursor, ''),
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }

    String marker = match.group(2)!;
    final RegExpMatch? number = _numbered.firstMatch(marker);
    if (number != null) {
      marker = '${int.parse(number.group(1)!) + 1}${number.group(2)}';
    }
    final String prefix =
        '${match.group(1)}$marker${match.group(3)}${match.group(4) != null ? '[ ] ' : ''}';

    return TextEditingValue(
      text: text.replaceRange(cursor, cursor, prefix),
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
  }
}
