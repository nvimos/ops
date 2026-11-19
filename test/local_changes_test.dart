import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/repo_backend.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/pr.dart';
import 'package:nvimos_poc/state/session.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

/// A repository opened with the local backend; closed (watcher included) before its folder goes.
Future<Session> openLocal(Directory repo) async {
  final s = Session();
  addTearDown(s.dispose);
  addTearDown(s.disconnect);
  await s.openFolder(repo.path);
  expect(s.conn, Conn.connected, reason: s.error);
  return s;
}

void main() {
  test('Changes: stage, unstage, hunks, discard and commit work against a local repository', () async {
    final repo = await makeRepo();
    final lines = List.generate(12, (i) => 'line ${i + 1}');
    await File('${repo.path}/a.txt').writeAsString('${lines.join('\n')}\n');
    await git(repo, ['commit', '-q', '-am', 'twelve']);
    lines[0] = 'LINE 1';
    lines[9] = 'LINE 10';
    await File('${repo.path}/a.txt').writeAsString('${lines.join('\n')}\n');
    await File('${repo.path}/b.txt').writeAsString('bee changed\n');
    await File('${repo.path}/new.txt').writeAsString('new\n');

    final s = await openLocal(repo);
    final st = ChangesState(s);
    addTearDown(st.dispose);
    await until(() => st.unstaged.length == 3 && st.diff != null);

    // a click changes the rows at once; git confirms after
    final staging = st.moveFile('b.txt', staged: false);
    expect(st.staged.map((f) => f.path), ['b.txt'], reason: 'the row moved before git answered');
    expect(st.busy, isTrue);
    expect(await staging, isNull);
    expect(st.busy, isFalse);
    expect(st.staged.map((f) => f.path), ['b.txt']);
    expect(await st.moveFile('b.txt', staged: true), isNull);
    expect(st.staged, isEmpty);

    // a failed action puts only its own rows back and says why
    final failing = st.act('stage', (b) => b.stage('no/such/file'), predict: (files) => []);
    expect(st.unstaged, isEmpty, reason: 'the prediction shows at once');
    expect(await failing, isNotNull);
    expect(st.unstaged.length, 3);

    // hunks
    st.select('a.txt', staged: false);
    await until(() => st.diff != null && st.diff!.hunks.length == 2 && st.selected == 'a.txt');
    expect(await st.toggleHunk(st.diff!.hunks.first), isNull);
    await until(() => st.staged.length == 1 && st.diff?.hunks.length == 1);
    expect(await git(repo, ['diff', '--cached', '--stat']), contains('a.txt'));
    expect(await st.commit('first hunk'), isNull);
    await until(() => st.staged.isEmpty);
    expect((await git(repo, ['log', '-1', '--format=%s'])).trim(), 'first hunk');

    st.select('a.txt', staged: false);
    await until(() => st.diff != null && st.diff!.hunks.length == 1 && st.selected == 'a.txt');
    expect(await st.discardHunk(st.diff!.hunks.single), isNull);
    await until(() => !st.unstaged.any((f) => f.path == 'a.txt'));
    expect(await File('${repo.path}/a.txt').readAsString(), contains('line 10'));

    // whole files: discard a tracked change, stage all, commit
    expect(await st.discardFile('b.txt'), isNull);
    await until(() => !st.unstaged.any((f) => f.path == 'b.txt'));
    expect(await File('${repo.path}/b.txt').readAsString(), 'bee\n');
    expect(await st.moveAll(staged: false), isNull);
    await until(() => st.staged.length == 1 && st.staged.single.path == 'new.txt');
    expect(await st.commit('add new'), isNull);
    await until(() => st.staged.isEmpty && st.unstaged.isEmpty);
  });

  test('Changes: checkout stashes or forces, and says no when git refuses', () async {
    final repo = await makeRepo();
    // the other branch changes a.txt too, so the uncommitted change is in git's way
    await git(repo, ['checkout', '-q', '-b', 'other']);
    await File('${repo.path}/a.txt').writeAsString('other side\n');
    await git(repo, ['commit', '-q', '-am', 'other']);
    await git(repo, ['checkout', '-q', 'main']);
    await File('${repo.path}/a.txt').writeAsString('dirty\n');

    final s = await openLocal(repo);
    final st = ChangesState(s);
    addTearDown(st.dispose);
    await until(() => st.unstaged.length == 1 && st.branchNames.contains('other'));
    expect([for (final f in st.wipedByCheckout) f.path], ['a.txt']);

    expect(await st.switchBranch('other'), isNotNull, reason: 'git refuses without a decision');
    expect(await st.switchBranch('other', how: CheckoutHow.stash), isNull);
    await until(() => st.status?.branch == 'other' && st.wipedByCheckout.isEmpty);
    expect(await git(repo, ['stash', 'list']), contains('before switching to other'));
  });

  test('Pull request: a clean merge works locally; a conflicting merge is aborted and reported', () async {
    final repo = await makeRepo();
    await git(repo, ['checkout', '-q', '-b', 'feature']);
    await File('${repo.path}/f.txt').writeAsString('feature\n');
    await git(repo, ['add', '.']);
    await git(repo, ['commit', '-q', '-m', 'feature']);
    await git(repo, ['checkout', '-q', 'main']);
    await File('${repo.path}/m.txt').writeAsString('main moved\n');
    await git(repo, ['add', '.']);
    await git(repo, ['commit', '-q', '-m', 'main moved']);

    final s = await openLocal(repo);
    final pr = PrState(s);
    addTearDown(pr.dispose);
    await until(() => !pr.loading && pr.diff != null);
    pr.pick(base: 'main', head: 'feature');
    await until(() => !pr.loading && pr.diff != null && pr.head == 'feature' && pr.canMerge);

    final merged = await pr.merge();
    expect(merged.error, isNull, reason: merged.error);
    expect((await git(repo, ['log', '-1', '--format=%s'])).trim(), contains('Merge'));
    expect(await File('${repo.path}/f.txt').exists(), isTrue);

    // a conflicting merge leaves the repository as it was
    await git(repo, ['checkout', '-q', '-b', 'clash', 'HEAD~1']);
    await File('${repo.path}/f.txt').writeAsString('clash\n');
    await git(repo, ['add', '.']);
    await git(repo, ['commit', '-q', '-m', 'clash']);
    await git(repo, ['checkout', '-q', 'main']);
    final before = (await git(repo, ['rev-parse', 'HEAD'])).trim();
    pr.pick(base: 'main', head: 'clash');
    await until(() => !pr.loading && pr.diff != null && pr.head == 'clash');
    final clashed = await pr.merge();
    expect(clashed.error, isNotNull);
    expect(clashed.error, contains('conflict'));
    expect((await git(repo, ['rev-parse', 'HEAD'])).trim(), before);
    expect((await git(repo, ['status', '--porcelain'])).trim(), isEmpty, reason: 'the merge was aborted');
  });
}
