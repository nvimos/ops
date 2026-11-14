import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/ui/syntax.dart';

DiffFile fileOf(String path, List<(String kind, String text)> lines) => DiffFile({
  'path': path,
  'hunks': [
    {
      'lines': [
        for (final (i, l) in lines.indexed) {'kind': l.$1, 'text': l.$2, 'old': i + 1, 'new': i + 1},
      ],
    },
  ],
});

/// The colors of the leaf spans of [s], in order.
List<(String, Color?)> leaves(TextSpan s) {
  final out = <(String, Color?)>[];
  void walk(InlineSpan x) {
    if (x is! TextSpan) return;
    if (x.text != null) out.add((x.text!, x.style?.color));
    x.children?.forEach(walk);
  }

  walk(s);
  return out;
}

void main() {
  test('the language comes from the file name', () {
    expect(languageOf('lib/main.dart'), 'dart');
    expect(languageOf('init.LUA'), 'lua');
    expect(languageOf('Makefile'), 'makefile');
    expect(languageOf('docs/notes.md'), 'markdown');
    expect(languageOf('README'), isNull);
    expect(languageOf('data.unknown'), isNull);
  });

  test('a Dart line gets a keyword color and a string color', () {
    final f = fileOf('a.dart', [('add', "final x = 'hi';")]);
    final s = DiffSyntax(f).spanOf(f.hunks.single.lines.single)!;
    final colors = {for (final (t, c) in leaves(s)) t: c};
    expect(colors['final'], syntaxTheme['keyword']!.color);
    expect(colors["'hi'"], syntaxTheme['string']!.color);
  });

  test('a comment over several lines colors the lines in its middle', () {
    final f = fileOf('a.dart', [('context', '/* one'), ('add', 'final is not a keyword here'), ('context', '*/ int y = 1;')]);
    final syn = DiffSyntax(f);
    final middle = syn.spanOf(f.hunks.single.lines[1])!;
    expect(leaves(middle).every((l) => l.$2 == syntaxTheme['comment']!.color), isTrue);
  });

  test('deletions are highlighted on the old side, additions on the new side', () {
    final f = fileOf('a.dart', [('del', "var s = '';"), ('add', "final s = '';")]);
    final syn = DiffSyntax(f);
    final del = leaves(syn.spanOf(f.hunks.single.lines[0])!);
    final add = leaves(syn.spanOf(f.hunks.single.lines[1])!);
    expect(del.first, ('var', syntaxTheme['keyword']!.color));
    expect(add.first, ('final', syntaxTheme['keyword']!.color));
  });

  test('an unknown language, a very long line and a missing newline', () {
    final plain = fileOf('notes.txt', [('add', 'final x')]);
    expect(DiffSyntax(plain).spanOf(plain.hunks.single.lines.single), isNull);

    final minified = fileOf('a.js', [('add', 'a' * 2000)]);
    expect(DiffSyntax(minified).spanOf(minified.hunks.single.lines.single), isNull);

    final noEol = DiffFile({
      'path': 'a.dart',
      'hunks': [
        {
          'lines': [
            {'kind': 'add', 'text': 'int x;', 'new': 1, 'no_eol': true},
          ],
        },
      ],
    });
    final s = DiffSyntax(noEol).spanOf(noEol.hunks.single.lines.single)!;
    expect(leaves(s).last.$1, contains('⏎'));
  });
}
