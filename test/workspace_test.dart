import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

/// A repo with a tiny planning layout, like nvimos-meta.
Future<Directory> planRepo() async {
  final d = await makeRepo();
  Future<void> w(String p, String s) async {
    await File('${d.path}/$p').create(recursive: true);
    await File('${d.path}/$p').writeAsString(s);
  }

  await w('backlog/config.yml', 'project_name: "demo"\nstatuses: ["To Do", "In Progress", "Needs Test", "Done"]\n');
  await w(
    'backlog/tasks/task-1 - first.md',
    '---\nid: TASK-1\ntitle: first\nstatus: To Do\nlabels: [a]\n---\n\n## Verify\n\n- [ ] try it\n',
  );
  await w('backlog/tasks/task-2 - second.md', '---\nid: TASK-2\ntitle: second\nstatus: In Progress\n---\n');
  await w(
    'openspec/changes/1-first/proposal.md',
    '# 1. first\n\nStatus: To Do (backlog TASK-1)\n\n## Why\n\nBecause.\n',
  );
  await w('openspec/changes/1-first/tasks.md', '# Tasks\n\n## 1. Build\n\n- [ ] 1.1 do\n');
  await w('legacy/todo-2027.md', '# 2027\n\n- [x] old thing; untested\n');
  await git(d, ['add', '.']);
  await git(d, ['commit', '-q', '-m', 'plan']);
  return d;
}

void main() {
  test('loads tasks, changes and legacy; links them; follows edits made outside', () async {
    final repo = await planRepo();
    await git(repo, ['branch', 'agent/task-1-first']);
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    // The Changes view runs git status on every hint; it must not keep the workspace loading.
    final changes = ChangesState(s);
    final ws = Workspace(s);
    await until(() => ws.loaded);
    expect(ws.projectName, 'demo');
    expect(ws.tasks.map((t) => t.id), ['TASK-1', 'TASK-2']);
    final t1 = ws.task('TASK-1')!;
    expect(ws.changeFor(t1)!.id, '1-first');
    expect(ws.branchFor(t1), 'agent/task-1-first');
    expect(ws.legacy.single.untested, isTrue);

    // An agent edits a task file outside Neovim: the workspace reloads on its own.
    await File('${repo.path}/backlog/tasks/task-2 - second.md')
        .writeAsString('---\nid: TASK-2\ntitle: second\nstatus: Needs Test\n---\n');
    await until(() => ws.task('TASK-2')?.status == 'Needs Test');
    await until(() => !ws.loading);

    ws.dispose();
    changes.dispose();
    s.dispose();
    await nvim.stop();
  });

  test('edits: status in task, proposal and index.tsv; checkbox; priority; create; stale edit refused', () async {
    final repo = await planRepo();
    await File('${repo.path}/index.tsv').writeAsString(
      ['task\tstatus\tchange\ttitle\tfile', 'TASK-1\tTo Do\t1-first\tfirst\tx.md', ''].join('\n'),
    );
    await git(repo, ['add', '.']);
    await git(repo, ['commit', '-q', '-m', 'index']);
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final ws = Workspace(s);
    await until(() => ws.loaded);
    String read(String p) => File('${repo.path}/$p').readAsStringSync();

    expect(await ws.setTaskStatus(ws.task('TASK-1')!, 'In Progress'), isNull);
    expect(ws.task('TASK-1')!.status, 'In Progress'); // in memory at once
    expect(read('backlog/tasks/task-1 - first.md'), contains('status: In Progress'));
    expect(read('openspec/changes/1-first/proposal.md'), contains('Status: In Progress (backlog TASK-1)'));
    expect(read('index.tsv'), contains('TASK-1\tIn Progress\t'));

    final check = ws.task('TASK-1')!.verify.single;
    expect(await ws.toggleCheck(ws.task('TASK-1')!.path, check), isNull);
    expect(read('backlog/tasks/task-1 - first.md'), contains('- [x] try it'));

    expect(await ws.setTaskPriority(ws.task('TASK-2')!, 'high'), isNull);
    expect(read('backlog/tasks/task-2 - second.md'), contains('priority: high'));

    final (err, id) = await ws.createTask(title: 'third: new', labels: ['x']);
    expect([err, id], [null, 'TASK-3']);
    expect(File('${repo.path}/backlog/tasks/task-3 - third-new.md').existsSync(), isTrue);

    // Someone changes the file behind the app's back: the edit is refused, nothing is lost.
    final t2 = ws.task('TASK-2')!;
    await File('${repo.path}/${t2.path}').writeAsString(read(t2.path).replaceFirst('status: In Progress', 'status: Done'));
    final stale = await ws.setTaskStatus(t2, 'Needs Test');
    expect(stale, contains('changed since'));
    await until(() => ws.task('TASK-2')?.status == 'Done');

    ws.dispose();
    s.dispose();
    await nvim.stop();
  });
}
