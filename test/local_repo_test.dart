import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/git_repo.dart';
import 'package:nvimos_poc/local/repo.dart';
import 'package:nvimos_poc/local/status.dart';
import 'package:nvimos_poc/local/system.dart';

import 'support/fake_system.dart';
import 'support/local_temp_repo.dart';

void main() {
  group('Repo', () {
    test('opens a repository and reports a clean tree', () async {
      final temp = await TempRepo.make();
      final repo = await Repo.open(temp.path);
      expect(repo.path.toLowerCase(), endsWith(temp.path.split('/').last.toLowerCase()));
      expect(await repo.status(), isEmpty);
    });

    test('an untracked file shows up as one untracked row', () async {
      final temp = await TempRepo.make();
      await temp.write('notes.md', 'hello\n');
      final repo = await Repo.open(temp.path);
      final rows = await repo.status();
      expect(rows.single.section, Section.untracked);
      expect(rows.single.path, 'notes.md');
    });

    test('status goes through the process runner, so a fake answers without git', () async {
      final temp = await TempRepo.make();
      final runner = FakeRunner((_) => const ProcessOutput(0, stdout: ' M a.txt\u0000'));
      final repo = await Repo.open(temp.path, runner: runner);
      final rows = await repo.status();
      expect(rows.single.path, 'a.txt');
      expect(runner.calls.single.line, contains('status'));
    });

    test('an ignored file is not listed', () async {
      final temp = await TempRepo.make();
      await temp.write('build/out.txt', 'x\n');
      final repo = await Repo.open(temp.path);
      expect(await repo.status(), isEmpty);
    });

    test('track stages a file, commit empties the list', () async {
      final temp = await TempRepo.make();
      await temp.write('a.txt', 'a\n');
      final repo = await Repo.open(temp.path);
      await repo.track(['a.txt']);
      final staged = await repo.status();
      expect(staged.single.section, Section.staged);
      await repo.commit('add a');
      expect(await repo.status(), isEmpty);
      final log = await temp.git(['log', '--oneline', '-1']);
      expect(log.stdout.toString(), contains('add a'));
    });

    test('untrack stops tracking but leaves the file on disk', () async {
      final temp = await TempRepo.make();
      await temp.write('keep.txt', 'k\n');
      final repo = await Repo.open(temp.path);
      await repo.track(['keep.txt']);
      await repo.commit('add keep');
      await repo.untrack(['keep.txt']);
      final rows = await repo.status();
      // The deletion is staged, and the file is back to being untracked.
      expect(rows.map((r) => r.section), [Section.staged, Section.untracked]);
      expect(rows.first.kind, RowKind.deleted);
      expect(await File('${temp.path}/keep.txt').exists(), isTrue);
    });

    test('checkIgnore names the file, line and pattern', () async {
      final temp = await TempRepo.make();
      await temp.write('.gitignore', 'build/\n*.log\n');
      await temp.write('run.log', 'x\n');
      final repo = await Repo.open(temp.path);
      final match = await repo.checkIgnore('run.log');
      expect(match, isNotNull);
      expect(match!.pattern, '*.log');
      expect(match.line, 2);
      expect(match.source, endsWith('.gitignore'));
    });

    test('checkIgnore returns null for a tracked path', () async {
      final temp = await TempRepo.make();
      final repo = await Repo.open(temp.path);
      expect(await repo.checkIgnore('.gitignore'), isNull);
    });

    test('appendIgnoreLine creates a file with a header and then appends', () async {
      final temp = await TempRepo.make();
      final repo = await Repo.open(temp.path);
      final nested = '${temp.path}/lib/generated/.gitignore';

      expect(await repo.appendIgnoreLine(nested, '/cache/'), IgnoreAppend.added);
      expect(await repo.appendIgnoreLine(nested, '*.g.dart'), IgnoreAppend.added);
      expect(await repo.appendIgnoreLine(nested, '*.g.dart'), IgnoreAppend.duplicate);

      final text = await File(nested).readAsString();
      expect(text, startsWith('# Purrage\n'));
      expect(text.split('\n').where((line) => line.isNotEmpty), [
        '# Purrage',
        '/cache/',
        '*.g.dart',
      ]);
    });

    group('the # Purrage section', () {
      Future<String> appendTo(String before, List<String> rules) async {
        final temp = await TempRepo.make();
        await temp.write('.gitignore', before);
        final repo = await Repo.open(temp.path);
        for (final rule in rules) {
          expect(await repo.appendIgnoreLine('${temp.path}/.gitignore', rule), IgnoreAppend.added);
        }
        return File('${temp.path}/.gitignore').readAsString();
      }

      test('a file without the section gets it at its end', () async {
        expect(
          await appendTo('build/\n*.log\n', ['/a.md', '/b.md']),
          'build/\n*.log\n# Purrage\n/a.md\n/b.md\n',
        );
      });

      test('a section at the end grows under its last rule', () async {
        expect(
          await appendTo('build/\n# Purrage\n/a.md\n', ['/b.md']),
          'build/\n# Purrage\n/a.md\n/b.md\n',
        );
      });

      test('a section in the middle grows in place, the rules below stay put', () async {
        expect(
          await appendTo('build/\n# Purrage\n/a.md\n\n# mine\n*.tmp\n', ['/b.md']),
          'build/\n# Purrage\n/a.md\n/b.md\n\n# mine\n*.tmp\n',
        );
      });

      test('CRLF is kept, and so is a missing final newline', () async {
        expect(
          await appendTo('build/\r\n*.log', ['/notes.md', '/b.md']),
          'build/\r\n*.log\r\n# Purrage\r\n/notes.md\r\n/b.md',
        );
      });

      test('a rule present outside the section is a duplicate', () async {
        final temp = await TempRepo.make();
        await temp.write('.gitignore', '/a.md\n# Purrage\n/b.md\n');
        final repo = await Repo.open(temp.path);
        final path = '${temp.path}/.gitignore';
        expect(await repo.appendIgnoreLine(path, '/a.md'), IgnoreAppend.duplicate);
        expect(await File(path).readAsString(), '/a.md\n# Purrage\n/b.md\n');
      });
    });

    test('commit takes the summary on stdin, so a leading dash is just text', () async {
      final temp = await TempRepo.make();
      await temp.write('a.txt', 'a\n');
      final repo = await Repo.open(temp.path);
      await repo.track(['a.txt']);
      await repo.commit('--amend is not an option here');
      expect(repo.lastCommand, 'git commit -F -');
      final log = await temp.git(['log', '--format=%s']);
      expect(log.stdout.toString().split('\n').first, '--amend is not an option here');
      expect(log.stdout.toString().trim().split('\n'), hasLength(2));
    });

    test('ignore an untracked nested repository: the rule is written and honoured', () async {
      final temp = await TempRepo.make();
      final inner = await _innerRepo(temp, 'es/inner');
      final repo = await Repo.open(temp.path);
      expect((await repo.status()).map((row) => row.path), contains('es/inner/'));

      // git answers this one with an empty pattern; that is not a rule.
      expect(await repo.checkIgnore('es/inner/'), isNull);
      expect(
        await repo.appendIgnoreLine('${temp.path}/.gitignore', '/es/inner/'),
        IgnoreAppend.added,
      );

      expect((await repo.status()).map((row) => row.path), ['.gitignore']);
      expect(await repo.checkIgnore('es/inner/'), isNotNull);
      expect(await File('${inner.path}/a.txt').exists(), isTrue);
    });

    test('untrack a nested repository: -f --cached, and the folder stays on disk', () async {
      final temp = await TempRepo.make();
      final inner = await _innerRepo(temp, 'inner');
      await temp.git(['add', 'inner']);
      await temp.git(['commit', '-m', 'add inner']);
      // Staged content that differs from HEAD and from the disk.
      await _innerCommit(inner, 'two');
      await temp.git(['add', 'inner']);
      await _innerCommit(inner, 'three');

      final repo = await Repo.open(temp.path);
      final before = await repo.status();
      expect(
        before.where((row) => row.section == Section.staged).map((row) => row.path),
        contains('inner'),
      );
      await repo.untrack(['inner']);

      expect(repo.lastCommand, 'git rm --cached -f -- inner');
      final after = await repo.status();
      expect(
        after.where((row) => row.section == Section.staged && row.kind != RowKind.deleted),
        isEmpty,
      );
      expect(await Directory(inner.path).exists(), isTrue);
      expect(await Directory('${inner.path}/.git').exists(), isTrue);
      expect(await File('${inner.path}/a.txt').readAsString(), 'three');
    });

    test('the ignore panes discovery splits tracked and untracked .gitignore files', () async {
      final temp = await TempRepo.make(withGitignore: false);
      await temp.write('.gitignore', 'build/\n');
      await temp.git(['add', '.gitignore']);
      await temp.write('lib/.gitignore', '/gen/\n');
      await temp.git(['add', 'lib/.gitignore']);
      await temp.write('web/.gitignore', 'dist/\n');
      final repo = await Repo.open(temp.path);

      expect(await repo.trackedGitignoreFiles(), ['.gitignore', 'lib/.gitignore']);
      expect(await repo.untrackedGitignoreFiles(), ['web/.gitignore']);

      // A tracked file deleted from disk is not offered: the pane would show a file that is gone.
      await File('${temp.path}/web/.gitignore').delete();
      await temp.git(['add', '-A']);
      await File('${temp.path}/lib/.gitignore').delete();
      expect(await repo.trackedGitignoreFiles(), ['.gitignore']);
      expect(await repo.untrackedGitignoreFiles(), isEmpty);
    });

    test('insertIgnoreLine keeps CRLF and a missing final newline', () async {
      final temp = await TempRepo.make(withGitignore: false);
      final path = '${temp.path}/.gitignore';
      await File(path).writeAsString('/a\r\n/b');
      final repo = await Repo.open(temp.path);

      await repo.insertIgnoreLine(path, 2, '/mid');
      expect(await File(path).readAsString(), '/a\r\n/mid\r\n/b');
      await repo.insertIgnoreLine(path, 4, '/last');
      expect(await File(path).readAsString(), '/a\r\n/mid\r\n/b\r\n/last');
      await repo.insertIgnoreLine(path, 1, '/first');
      expect(await File(path).readAsString(), '/first\r\n/a\r\n/mid\r\n/b\r\n/last');
      expect(() => repo.insertIgnoreLine(path, 99, 'x'), throwsA(isA<GitException>()));
    });

    test('insertIgnoreLine gives an empty file one line', () async {
      final temp = await TempRepo.make(withGitignore: false);
      final repo = await Repo.open(temp.path);
      await repo.insertIgnoreLine('${temp.path}/new/.gitignore', 1, '/x');
      expect(await File('${temp.path}/new/.gitignore').readAsString(), '/x\n');
    });

    test('a nested rule can be written and git honours it', () async {
      final temp = await TempRepo.make();
      await temp.write('lib/generated/a.g.dart', 'x\n');
      final repo = await Repo.open(temp.path);
      final targets = await repo.gitignoreFiles();
      expect(targets, contains('.gitignore'));
      final nested = '${temp.path}/lib/generated/.gitignore';
      await repo.appendIgnoreLine(nested, '/a.g.dart');
      expect(await repo.checkIgnore('lib/generated/a.g.dart'), isNotNull);
      final rows = await repo.status();
      expect(rows.map((r) => r.path), isNot(contains('lib/generated/a.g.dart')));
    });
  });

  group('one git call per action', () {
    test('untrack takes paths with spaces and non-ASCII in one call', () async {
      final temp = await TempRepo.make();
      await temp.write('my notes.txt', 'n\n');
      await temp.write('ærø/blåbær.txt', 'b\n');
      final repo = await Repo.open(temp.path);
      await repo.track(['my notes.txt', 'ærø/blåbær.txt']);
      await repo.commit('add two');
      await repo.untrack(['my notes.txt', 'ærø/blåbær.txt']);
      expect(repo.lastCommand, startsWith('git rm --cached -- '));
      final rows = await repo.status();
      expect(
        rows.where((r) => r.section == Section.staged).map((r) => r.path),
        unorderedEquals(['my notes.txt', 'ærø/blåbær.txt']),
      );
      expect(await File('${temp.path}/ærø/blåbær.txt').exists(), isTrue);
    });

    test('a batch with a nested repository is retried with -f, and both leave the index', () async {
      final temp = await TempRepo.make();
      await temp.write('plain.txt', 'p\n');
      final inner = await TempRepo.nested(temp, 'inner');
      await inner.write('a.txt', 'one');
      await inner.git(['add', '-A']);
      await inner.git(['commit', '-qm', 'one']);
      await temp.git(['add', 'plain.txt', 'inner']);
      await temp.git(['commit', '-qm', 'add inner']);
      // The staged gitlink now differs from HEAD and from the working tree.
      await inner.write('a.txt', 'two');
      await inner.git(['add', '-A']);
      await inner.git(['commit', '-qm', 'two']);
      await temp.git(['add', 'inner']);

      final repo = await Repo.open(temp.path);
      await repo.untrack(['plain.txt', 'inner']);
      expect(repo.lastCommand, contains('-f'));
      final index = (await temp.git(['ls-files', '--stage'])).stdout.toString();
      expect(index, isNot(contains('plain.txt')));
      expect(index, isNot(contains('inner')));
      expect(await Directory('${temp.path}/inner/.git').exists(), isTrue);
    });

    test('checkIgnoreAll answers every path from one process, keyed as asked', () async {
      final temp = await TempRepo.make();
      await temp.write('.gitignore', 'build/\n*.log\n');
      await temp.write('run.log', 'x\n');
      await temp.write('logs dir/åpen.log', 'x\n');
      await temp.write('keep.txt', 'x\n');
      await temp.write('cache/a.bin', 'x\n');
      await temp.write('build/out.txt', 'x\n');
      final repo = await Repo.open(temp.path);
      final found = await repo.checkIgnoreAll(
        ['run.log', 'logs dir/åpen.log', 'keep.txt', 'cache/', 'build/'],
      );
      expect(repo.lastCommand, contains('--stdin'));
      expect(found.keys, unorderedEquals(['run.log', 'logs dir/åpen.log', 'build/']));
      expect(found['run.log']!.line, 2);
      expect(found['logs dir/åpen.log']!.pattern, '*.log');
      // The trailing slash is stripped before asking, and the answer is keyed
      // by the path as it was given.
      expect(found['build/']!.pattern, 'build/');
    });

    test('checkIgnoreAll reads a source that starts with a drive letter', () async {
      final temp = await TempRepo.make();
      final excludes = '${temp.path}/excludes.txt';
      await temp.write('excludes.txt', '*.tmp\n');
      await temp.git(['config', 'core.excludesFile', excludes]);
      await temp.write('scratch.tmp', 'x\n');
      final repo = await Repo.open(temp.path);
      final found = await repo.checkIgnoreAll(['scratch.tmp']);
      expect(found['scratch.tmp']!.source.toLowerCase(), excludes.toLowerCase());
      expect(found['scratch.tmp']!.line, 1);
      expect(found['scratch.tmp']!.pattern, '*.tmp');
    });

    test('appendIgnoreLines reads and writes once, dropping duplicates, keeping CRLF', () async {
      final temp = await TempRepo.make();
      await temp.write('.gitignore', 'build/\r\n*.log\r\n');
      final repo = await Repo.open(temp.path);
      final answers = await repo.appendIgnoreLines(
        '${temp.path}/.gitignore',
        ['/a.txt', '*.log', '/b.txt', '/a.txt'],
      );
      expect(answers, [
        IgnoreAppend.added,
        IgnoreAppend.duplicate,
        IgnoreAppend.added,
        IgnoreAppend.duplicate,
      ]);
      final text = await File('${temp.path}/.gitignore').readAsString();
      expect(text, 'build/\r\n*.log\r\n# Purrage\r\n/a.txt\r\n/b.txt\r\n');
    });
  });

  group('IgnoreMatch.parseZ', () {
    test('reads NUL records, with a C:/ source, and drops the non-matching ones', () {
      const raw = 'C:/Users/me/.config/git/ignore\u00003\u0000*.log\u0000run.log\u0000'
          '\u0000\u0000\u0000keep.txt\u0000'
          '.gitignore\u00001\u0000build/\u0000build\u0000';
      final found = IgnoreMatch.parseZ(raw);
      expect(found, hasLength(2));
      expect(found.first.source, 'C:/Users/me/.config/git/ignore');
      expect(found.first.line, 3);
      expect(found.first.pattern, '*.log');
      expect(found.first.path, 'run.log');
      expect(found.last.path, 'build');
    });

    test('an empty pattern is not a rule', () {
      const raw = '.gitignore\u000012\u0000\u0000es/inner\u0000';
      expect(IgnoreMatch.parseZ(raw), isEmpty);
    });

    test('empty output is no match', () {
      expect(IgnoreMatch.parseZ(''), isEmpty);
    });
  });

  group('Repo.argumentBatches', () {
    test('a short list is one batch', () {
      expect(Repo.argumentBatches(['a', 'b', 'c']), [
        ['a', 'b', 'c'],
      ]);
    });

    test('a long list is split under the limit, keeping the order', () {
      final paths = [for (var i = 0; i < 1000; i++) 'folder/sub/file_$i.dart'];
      final batches = Repo.argumentBatches(paths, limit: 3000);
      expect(batches.length, greaterThan(1));
      expect(batches.expand((batch) => batch), paths);
      for (final batch in batches) {
        expect(batch.fold<int>(0, (sum, path) => sum + path.length + 3), lessThanOrEqualTo(3000));
      }
    });

    test('nothing is no batch', () {
      expect(Repo.argumentBatches(const []), isEmpty);
    });
  });
}

/// A repository of its own at [relative] inside [temp], with one commit.
Future<Directory> _innerRepo(TempRepo temp, String relative) async {
  final inner = Directory('${temp.dir.path}/$relative');
  await inner.create(recursive: true);
  await _innerGit(inner, ['init', '-q', '-b', 'main']);
  await _innerGit(inner, ['config', 'user.email', 'testies@example.com']);
  await _innerGit(inner, ['config', 'user.name', 'Testies Cohones']);
  await _innerGit(inner, ['config', 'core.fsmonitor', 'false']);
  await _innerCommit(inner, 'one');
  return inner;
}

Future<void> _innerCommit(Directory inner, String text) async {
  await File('${inner.path}/a.txt').writeAsString(text);
  await _innerGit(inner, ['add', '-A']);
  await _innerGit(inner, ['commit', '-qm', text]);
}

Future<void> _innerGit(Directory dir, List<String> args) async {
  final result = await Process.run(
    'git',
    ['-c', 'core.fsmonitor=false', ...args],
    workingDirectory: dir.path,
  );
  if (result.exitCode != 0) throw StateError('git ${args.join(' ')}: ${result.stderr}');
}
