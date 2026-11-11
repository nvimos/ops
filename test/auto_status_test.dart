import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/auto_status.dart';
import 'package:nvimos_poc/tasks/markdown.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

List<Check> checks(String marks) => [for (var i = 0; i < marks.length; i++) Check(i, marks[i] == 'x', 'c$i', 0)];

String? next(String status, String build, String verify) =>
    autoStatusAfterTick(status: status, build: checks(build), verify: checks(verify), statuses: defaultStatuses);

void main() {
  test('autoStatusAfterTick: Needs Test when only hand checks are left, Done when nothing is', () {
    expect(next('To Do', 'xx', '  '), 'Needs Test');
    expect(next('In Progress', 'xx', 'x '), 'Needs Test');
    expect(next('Needs Test', 'xx', 'xx'), 'Done');
    expect(next('To Do', 'xx', ''), 'Done');
    expect(next('To Do', '', 'x'), 'Done');
    expect(next('To Do', 'x ', ''), isNull, reason: 'a build step is open');
    expect(next('Needs Test', 'xx', 'x '), isNull, reason: 'already there');
    expect(next('Dropped', 'xx', 'xx'), isNull, reason: 'never out of Dropped');
    expect(next('Done', 'xx', 'xx'), isNull);
    expect(next('To Do', '', ''), isNull, reason: 'no boxes at all');
    expect(
      autoStatusAfterTick(status: 'To Do', build: checks('x'), verify: [], statuses: ['To Do', 'Done']),
      'Done',
    );
    expect(
      autoStatusAfterTick(status: 'To Do', build: checks('x'), verify: checks(' '), statuses: ['To Do', 'Done']),
      isNull,
      reason: 'no Needs Test status in this workspace',
    );
  });

  test('ticking the last boxes moves the task on, in the task and through its change; undo puts it back', () async {
    final repo = await makeRepo();
    Future<void> w(String p, String s) async {
      await File('${repo.path}/$p').create(recursive: true);
      await File('${repo.path}/$p').writeAsString(s);
    }

    await w(
      'backlog/tasks/task-1 - one.md',
      '---\nid: TASK-1\ntitle: one\nstatus: In Progress\n---\n\n## Acceptance Criteria\n\n- [ ] #1 build it\n\n'
          '## Verify\n\n- [ ] try it\n',
    );
    await w('backlog/tasks/task-2 - two.md', '---\nid: TASK-2\ntitle: two\nstatus: To Do\n---\n');
    await w('openspec/changes/two/proposal.md', '# two\n\nStatus: To Do (backlog TASK-2)\n');
    await w('openspec/changes/two/tasks.md', '# Tasks\n\n## 1. Build\n\n- [ ] 1.1 do\n\n## 2. Verify\n\n- [ ] 2.1 try\n');
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final ws = Workspace(s);
    await until(() => ws.loaded);

    final t1 = ws.task('TASK-1')!;
    expect(await ws.toggleCheck(t1.path, t1.acceptance.single), isNull);
    expect(ws.task('TASK-1')!.status, 'Needs Test');
    expect(ws.autoStatus.value!.to, 'Needs Test');
    expect(await ws.toggleCheck(t1.path, ws.task('TASK-1')!.verify.single), isNull);
    expect(ws.task('TASK-1')!.status, 'Done');
    expect(await ws.undoAutoStatus(ws.autoStatus.value!), isNull);
    expect(ws.task('TASK-1')!.status, 'Needs Test');

    // Unticking leaves the status alone.
    ws.autoStatus.value = null;
    expect(await ws.toggleCheck(t1.path, ws.task('TASK-1')!.verify.single), isNull);
    expect(ws.task('TASK-1')!.status, 'Needs Test');
    expect(ws.autoStatus.value, isNull);

    // A change's tasks.md moves its task, and the proposal's Status line with it.
    final c = ws.changeFor(ws.task('TASK-2')!)!;
    Check box(String group) => ws.changeFor(ws.task('TASK-2')!)!.checkGroups.firstWhere((g) => g.$1 == group).$2.single;
    expect(await ws.toggleCheck(c.tasks!.path, box('Build')), isNull);
    expect(ws.task('TASK-2')!.status, 'Needs Test');
    expect(await ws.toggleCheck(c.tasks!.path, box('Verify')), isNull);
    expect(ws.task('TASK-2')!.status, 'Done');
    expect(ws.changeFor(ws.task('TASK-2')!)!.status, 'Done');
    await until(() => File('${repo.path}/openspec/changes/two/proposal.md').readAsStringSync().contains('Status: Done'));

    ws.dispose();
    s.dispose();
    await nvim.stop();
  });
}
