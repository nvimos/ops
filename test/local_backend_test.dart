import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/local_backend.dart';
import 'package:nvimos_poc/local/system.dart';

import 'support/fake_system.dart';
import 'support/local_temp_repo.dart';

void main() {
  test('a fake runner answers log and diff', () async {
    final temp = await TempRepo.make();
    final runner = FakeRunner((call) {
      if (call.args.first == 'log') {
        return const ProcessOutput(0, stdout: 'abc123\u001fabc\u001fA\u001f1700000000\u001fa commit\u001e');
      }
      if (call.args.first == 'merge-base') return const ProcessOutput(0, stdout: 'base123\n');
      if (call.args.first == 'diff') {
        return const ProcessOutput(
          0,
          stdout: 'diff --git a/a.txt b/a.txt\n'
              '--- a/a.txt\n'
              '+++ b/a.txt\n'
              '@@ -1 +1 @@\n'
              '-old\n'
              '+new\n',
        );
      }
      return const ProcessOutput(1, stderr: 'unexpected');
    });
    final backend = await LocalBackend.open(temp.path, runner: runner);
    addTearDown(backend.close);

    final commits = await backend.log('main', 'head');
    expect(commits.single.sha, 'abc123');
    expect(commits.single.subject, 'a commit');

    final diff = await backend.diff('main', 'head');
    expect(diff.mergeBase, 'base123');
    expect(diff.files.single.path, 'a.txt');
  });

  test('stage, unstage and discard leave the expected rows', () async {
    final temp = await TempRepo.make();
    await temp.write('a.txt', 'a\n');
    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);

    await backend.stage('a.txt');
    var status = await backend.status();
    expect(status.files.single.path, 'a.txt');
    expect(status.files.single.staged, isTrue);

    await backend.unstage('a.txt');
    status = await backend.status();
    expect(status.files.single.untracked, isTrue);

    await backend.discard('a.txt');
    status = await backend.status();
    expect(status.files, isEmpty);
    expect(File('${temp.path}/a.txt').existsSync(), isFalse);
  });

  test('discard restores a tracked file and stages a deletion', () async {
    final temp = await TempRepo.make();
    await temp.write('a.txt', 'one\n');
    await temp.git(['add', 'a.txt']);
    await temp.git(['commit', '-m', 'a']);
    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);

    await temp.write('a.txt', 'two\n');
    await backend.discard('a.txt');
    expect(await File('${temp.path}/a.txt').readAsString(), 'one\n');

    await File('${temp.path}/a.txt').delete();
    await backend.stage('a.txt');
    final status = await backend.status();
    expect(status.files.single.path, 'a.txt');
    expect(status.files.single.staged, isTrue);
  });

  test('read-only queries answer from the repository', () async {
    final temp = await TempRepo.make();
    await temp.write('a.txt', 'one\ntwo\n');
    await temp.git(['add', 'a.txt']);
    await temp.git(['commit', '-m', 'add a']);
    final second = _sha(await temp.git(['rev-parse', 'HEAD']));

    await temp.git(['branch', 'feature']);
    await temp.write('a.txt', 'one\ntwo\nthree\n');
    await temp.git(['add', 'a.txt']);
    await temp.git(['commit', '-m', 'extend a']);
    final head = _sha(await temp.git(['rev-parse', 'HEAD']));

    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);

    final branches = await backend.branches();
    expect(branches.current, 'main');
    expect(branches.list.map((branch) => branch.name), containsAll(['main', 'feature']));
    expect(branches.list.firstWhere((branch) => branch.name == 'main').sha, head);

    final commits = await backend.log('feature', 'main');
    expect(commits.map((commit) => commit.subject), ['extend a']);
    expect(commits.single.sha, head);

    final diff = await backend.diff('feature', 'main');
    expect(diff.base, 'feature');
    expect(diff.head, 'main');
    expect(diff.mergeBase, second);
    final changed = diff.files.firstWhere((file) => file.path == 'a.txt');
    expect(changed.hunks, isNotEmpty);
    expect(changed.additions, greaterThan(0));

    await temp.write('a.txt', 'one\ntwo\nthree\nfour\n');
    await temp.write('staged.txt', 'staged\n');
    await temp.git(['add', 'staged.txt']);
    await temp.write('untracked.txt', 'untracked\n');

    final status = await backend.status();
    expect(status.branch, 'main');

    final staged = status.files.firstWhere((file) => file.path == 'staged.txt');
    expect(staged.staged, isTrue);
    expect(staged.unstaged, isFalse);
    expect(staged.index, 'A');
    expect(staged.worktree, ' ');

    final unstaged = status.files.firstWhere((file) => file.path == 'a.txt');
    expect(unstaged.staged, isFalse);
    expect(unstaged.unstaged, isTrue);
    expect(unstaged.index, ' ');
    expect(unstaged.worktree, 'M');

    final untracked = status.files.firstWhere((file) => file.path == 'untracked.txt');
    expect(untracked.untracked, isTrue);
    expect(untracked.unstaged, isTrue);
    expect(untracked.index, '?');
    expect(untracked.worktree, '?');

    final changedDiff = await backend.diffFile('a.txt', staged: false);
    expect(changedDiff, isNotNull);
    expect(changedDiff!.path, 'a.txt');
    expect(changedDiff.hunks, isNotEmpty);

    final addedDiff = await backend.diffFile('staged.txt', staged: true);
    expect(addedDiff, isNotNull);
    expect(addedDiff!.path, endsWith('staged.txt'));

    final untrackedDiff = await backend.diffFile('untracked.txt', staged: false);
    expect(untrackedDiff, isNotNull);
    expect(untrackedDiff!.path, endsWith('untracked.txt'));

    final tracking = await backend.tracking();
    expect(tracking.repoRoot, isNotEmpty);
    expect(tracking.root, isNotEmpty);

    final dirs = await backend.dirs();
    expect(dirs.source, 'local');
    expect(dirs.dirs, [backend.root]);
    expect(await backend.pluginRoot(), isNull);
  });

  test('remaining actions throw until their tasks', () async {
    final temp = await TempRepo.make();
    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);

    await expectLater(backend.commit('message'), throwsUnimplementedError);
    await expectLater(backend.checkout('main'), throwsUnimplementedError);
  });
}

String _sha(ProcessResult result) => result.stdout.toString().trim();
