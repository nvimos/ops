import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/local_backend.dart';

import 'support/local_temp_repo.dart';

void main() {
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

  test('actions that change the repository throw until TASK-163', () async {
    final temp = await TempRepo.make();
    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);

    await expectLater(backend.stage('a.txt'), throwsUnimplementedError);
    await expectLater(backend.commit('message'), throwsUnimplementedError);
    await expectLater(backend.checkout('main'), throwsUnimplementedError);
  });
}

String _sha(ProcessResult result) => result.stdout.toString().trim();
