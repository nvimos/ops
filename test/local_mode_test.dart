import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/pr.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'workspace_test.dart' show planRepo;

void main() {
  test('Pull request, Changes and Tasks load a local repository, and follow edits made outside', () async {
    final repo = await planRepo();
    await git(repo, ['checkout', '-q', '-b', 'feature']);
    await File('${repo.path}/a.txt').writeAsString('one\ntwo\nTHREE\nfour\nfive\n');
    await git(repo, ['commit', '-q', '-am', 'feature work']);
    await git(repo, ['checkout', '-q', 'main']);
    await git(repo, ['branch', 'agent/task-1-first']);
    await File('${repo.path}/b.txt').writeAsString('bee changed\n');
    await File('${repo.path}/new.txt').writeAsString('brand new\n');

    final s = Session();
    addTearDown(s.dispose);
    addTearDown(s.disconnect); // runs first: the watcher lets go of the folder before it is deleted
    await s.openFolder(repo.path);
    expect(s.conn, Conn.connected, reason: s.error);
    expect(s.hasEditor, isTrue, reason: 'an external editor from Settings');

    // Pull request: branches, commits and a diff, no editor involved
    final pr = PrState(s);
    addTearDown(pr.dispose);
    await until(() => !pr.loading && pr.diff != null);
    pr.pickHead('feature');
    await until(() => !pr.loading && pr.diff != null && pr.head == 'feature');
    expect([pr.base, pr.head], ['main', 'feature']);
    expect(pr.commits.map((c) => c.subject), ['feature work']);
    expect(pr.diff!.files.map((f) => f.path), ['a.txt']);

    // Changes: staged, changed and untracked rows
    final changes = ChangesState(s);
    addTearDown(changes.dispose);
    await until(() => changes.unstaged.length == 2);
    expect(changes.unstaged.map((f) => f.path), unorderedEquals(['b.txt', 'new.txt']));
    expect(changes.unstaged.singleWhere((f) => f.path == 'new.txt').untracked, isTrue);
    await until(() => changes.diff != null);

    // Tasks: the planning folder and its links
    final ws = Workspace(s);
    addTearDown(ws.dispose);
    await until(() => ws.loaded);
    expect(ws.projectName, 'demo');
    expect(ws.tasks.map((t) => t.id), ['TASK-1', 'TASK-2']);
    final t1 = ws.task('TASK-1')!;
    expect(ws.changeFor(t1)!.id, '1-first');
    expect(ws.branchFor(t1), 'agent/task-1-first');

    // An edit made outside Ops reaches the views through the repository watcher
    await File('${repo.path}/c.txt').writeAsString('from a terminal\n');
    await until(() => changes.unstaged.any((f) => f.path == 'c.txt'));
    await File('${repo.path}/backlog/tasks/task-2 - second.md')
        .writeAsString('---\nid: TASK-2\ntitle: second\nstatus: Needs Test\n---\n');
    await until(() => ws.task('TASK-2')?.status == 'Needs Test');
    expect(s.changedPaths.value, isNotEmpty, reason: 'the Tasks hint has a local value');

    // a commit made in a terminal shows up as a new HEAD
    await git(repo, ['add', 'c.txt']);
    await git(repo, ['commit', '-q', '-m', 'from a terminal']);
    await until(() => changes.unstaged.every((f) => f.path != 'c.txt') && changes.staged.isEmpty);
  });
}
