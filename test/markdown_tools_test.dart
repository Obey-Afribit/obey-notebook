import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_notebook/core/list_continuation.dart';
import 'package:universal_notebook/core/markdown_tools.dart';

void main() {
  group('Task lists', () {
    const String source = '# Shop\n'
        '- [ ] milk\n'
        '- [x] eggs\n'
        '```\n'
        '- [ ] not a real task (inside code)\n'
        '```\n'
        '1. [ ] numbered task';

    test('counts tasks outside code blocks only', () {
      expect(MarkdownTools.countTasks(source), 3);
      final TaskProgress progress = MarkdownTools.taskProgress(source);
      expect(progress.done, 1);
      expect(progress.total, 3);
    });

    test('toggles the right task by document order', () {
      final String once = MarkdownTools.toggleTask(source, 0);
      expect(once, contains('- [x] milk'));
      final String twice = MarkdownTools.toggleTask(once, 1);
      expect(twice, contains('- [ ] eggs'));
      final String third = MarkdownTools.toggleTask(twice, 2);
      expect(third, contains('1. [x] numbered task'));
      expect(third, contains('- [ ] not a real task'));
    });

    test('out-of-range toggle is a no-op', () {
      expect(MarkdownTools.toggleTask(source, 9), source);
    });
  });

  group('Previews and counts', () {
    test('preview strips Markdown and images', () {
      const String body = '## Title\n\n**Bold** and _italic_ with a [link](https://x.y)\n\n'
          '![image](https://example.com/a.png)\n- [ ] task';
      final String preview = MarkdownTools.previewText(body);
      expect(preview, isNot(contains('!')));
      expect(preview, isNot(contains('**')));
      expect(preview, contains('Bold and italic with a link'));
      expect(preview, contains('task'));
    });

    test('image urls and removal', () {
      const String body = 'a\n\n![image](https://s/1.png)\n\nb ![x](https://s/2.png)';
      expect(MarkdownTools.imageUrls(body), <String>['https://s/1.png', 'https://s/2.png']);
      final String removed = MarkdownTools.removeImage(body, 'https://s/1.png');
      expect(removed, isNot(contains('1.png')));
      expect(removed, contains('2.png'));
    });

    test('word count ignores markup', () {
      expect(MarkdownTools.wordCount('# Hello world\n\n- [ ] buy **milk**'), 4);
      expect(MarkdownTools.readingMinutes(0), 0);
      expect(MarkdownTools.readingMinutes(10), 1);
      expect(MarkdownTools.readingMinutes(500), 3);
    });
  });

  group('List continuation', () {
    final ListContinuationFormatter formatter = ListContinuationFormatter();

    TextEditingValue type(String before) {
      final TextEditingValue old = TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      );
      final TextEditingValue next = TextEditingValue(
        text: '$before\n',
        selection: TextSelection.collapsed(offset: before.length + 1),
      );
      return formatter.formatEditUpdate(old, next);
    }

    test('continues bullets, tasks and numbers', () {
      expect(type('- apples').text, '- apples\n- ');
      expect(type('- [x] done').text, '- [x] done\n- [ ] ');
      expect(type('9. nine').text, '9. nine\n10. ');
      expect(type('  * nested').text, '  * nested\n  * ');
    });

    test('Enter on an empty item ends the list', () {
      final TextEditingValue result = type('- one\n- ');
      expect(result.text, '- one\n');
      expect(result.selection.baseOffset, 6);
    });

    test('plain lines and pastes are untouched', () {
      expect(type('hello').text, 'hello\n');
      const TextEditingValue old = TextEditingValue(
        text: '- a',
        selection: TextSelection.collapsed(offset: 3),
      );
      const TextEditingValue pasted = TextEditingValue(
        text: '- a\nline two\n',
        selection: TextSelection.collapsed(offset: 13),
      );
      expect(formatter.formatEditUpdate(old, pasted).text, pasted.text);
    });
  });
}
