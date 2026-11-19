import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/local/ignore_edits.dart';

StatusFile untracked(String path) => StatusFile({'path': path, 'index': '?', 'worktree': '?', 'untracked': true});
StatusFile changed(String path) => StatusFile({'path': path, 'worktree': 'M', 'unstaged': true});

void main() {
  group('dirname', () {
    String? up(String line) => IgnoreEdits.dirname(line).text;
    String? no(String line) => IgnoreEdits.dirname(line).refusal;

    test('takes the last component off a rule and keeps it a folder rule', () {
      expect(up('/a/b/x.log'), '/a/b/');
      expect(up('a/b'), 'a/');
      expect(up('/build/out/'), '/build/');
      expect(up('/build/out/x.log'), '/build/out/');
      expect(up('a/*/b'), 'a/*/');
    });

    test('trims leading spaces, as the rules engine does', () {
      expect(up('  /a/b/'), '/a/');
      expect(up('\t/x/y'), '/x/');
    });

    test('an escaped # or ! is a positive rule, not a comment or a negation', () {
      expect(up(r'\#a/b'), r'\#a/');
      expect(up(r'\!a/b'), r'\!a/');
      expect(no(r'\#file'), IgnoreRefusal.noParent);
      expect(no(r'\!file'), IgnoreRefusal.noParent);
    });

    test('refuses comments and blank lines', () {
      expect(no('# a comment'), IgnoreRefusal.notPositive);
      expect(no('  # a comment'), IgnoreRefusal.notPositive);
      expect(no(''), IgnoreRefusal.notPositive);
      expect(no('   '), IgnoreRefusal.notPositive);
    });

    test('refuses negations', () {
      expect(no('!a/b'), IgnoreRefusal.negation);
      expect(no('  !*.log'), IgnoreRefusal.negation);
    });

    test('refuses a rule with no folder above it', () {
      expect(no('*.log'), IgnoreRefusal.noParent);
      expect(no('/x.log'), IgnoreRefusal.noParent);
      expect(no('build/'), IgnoreRefusal.noParent);
      expect(no('**/'), IgnoreRefusal.noParent);
    });

    test('refuses a wildcard-only parent', () {
      expect(no('**/x.log'), IgnoreRefusal.wildcard);
      expect(no('[ab]/x.log'), IgnoreRefusal.wildcard);
      expect(no('?/x.log'), IgnoreRefusal.wildcard);
    });
  });

  group('flip', () {
    String? flipped(String line) => IgnoreEdits.flip(line).text;
    String? no(String line) => IgnoreEdits.flip(line).refusal;

    test('toggles the leading ! on a rule', () {
      expect(flipped('*.log'), '!*.log');
      expect(flipped('!*.log'), '*.log');
      expect(flipped('/a/b/'), '!/a/b/');
      expect(flipped('  /a/b/'), '!/a/b/');
    });

    test('an escaped ! is a positive rule, so it gains the negation', () {
      expect(flipped(r'\!a'), r'!\!a');
      expect(flipped(r'\\#a'), r'!\\#a');
    });

    test('refuses comments and blank lines', () {
      expect(no('# x'), IgnoreRefusal.notRule);
      expect(no('  # x'), IgnoreRefusal.notRule);
      expect(no(''), IgnoreRefusal.notRule);
      expect(no('   '), IgnoreRefusal.notRule);
    });
  });

  group('lineAfterWrite', () {
    test('finds the exact rule line with CRLF', () {
      expect(IgnoreEdits.lineAfterWrite('a\r\nb\r\n', ['b'], added: [true]), 2);
      expect(IgnoreEdits.lineOfRule('a\r\nb\r\n', 'b'), 2);
    });

    test('finds it without a final newline', () {
      expect(IgnoreEdits.lineAfterWrite('a\nb', ['b'], added: [true]), 2);
    });

    test('several rules: the first new one', () {
      const text = '# Purrage\n/a\n/b\n';
      expect(IgnoreEdits.lineAfterWrite(text, ['/a', '/b'], added: [true, true]), 2);
    });

    test('a duplicate writes nothing new, so there is no line', () {
      expect(IgnoreEdits.lineAfterWrite('a\n', ['a'], added: [false]), isNull);
      expect(IgnoreEdits.lineAfterWrite('a\nb\n', ['a', 'b'], added: [false, true]), 2);
    });
  });

  group('ignoreEffect', () {
    test('counts the untracked rows that left the list', () {
      final effect = IgnoreEffect.between([untracked('a'), untracked('b')], [untracked('b')]);
      expect(effect.lost, 1);
      expect(effect.gained, 0);
      expect(effect.message, '1 file now ignored');
    });

    test('counts the rows that came back', () {
      final effect = IgnoreEffect.between([untracked('a'), changed('x')], [untracked('a'), untracked('b'), untracked('c')]);
      expect(effect.gained, 2);
      expect(effect.lost, 0);
      expect(effect.message, '2 files back in the list');
    });

    test('says both when both moved, and nothing when none did', () {
      final effect = IgnoreEffect.between([untracked('a')], [untracked('b')]);
      expect(effect.message, '1 file now ignored · 1 file back in the list');
      expect(IgnoreEffect.between([untracked('a')], [untracked('a')]).message, isNull);
    });
  });
}
