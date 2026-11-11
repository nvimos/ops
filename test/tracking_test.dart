import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/parse.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

/// A planning folder shared by two projects, and a code repo whose `.nvimos` points at it.
Future<(Directory, Directory)> sharedPlanning() async {
  final plan = await Directory.systemTemp.createTemp('nvimos_plan_');
  Future<void> w(String p, String s) async {
    await File('${plan.path}/$p').create(recursive: true);
    await File('${plan.path}/$p').writeAsString(s);
  }

  await w('backlog/config.yml', 'project_name: "meta"\nprojects: [frontend, nvim-config]\n');
  await w('backlog/tasks/task-1 - ui.md', '---\nid: TASK-1\ntitle: ui\nstatus: To Do\nlabels: [frontend]\n---\n');
  await w('backlog/tasks/task-2 - keys.md', '---\nid: TASK-2\ntitle: keys\nstatus: To Do\nlabels: [nvim-config, lua]\n---\n');
  await w('backlog/tasks/task-7 - both.md', '---\nid: TASK-7\ntitle: both\nstatus: To Do\nlabels: [docs]\n---\n');
  await w('openspec/changes/keys/proposal.md', '# keys\n\nStatus: To Do (backlog TASK-2)\n');
  await w('openspec/changes/ui/proposal.md', '# ui\n\nStatus: To Do (backlog TASK-1)\n');
  final code = await makeRepo();
  final path = plan.path.replaceAll('\\', '/');
  await File('${code.path}/.nvimos').writeAsString('# where the planning lives\ntracking = $path\nproject = frontend\n');
  return (code, plan);
}

void main() {
  test('parseBacklogProjects reads projects: from config.yml', () {
    expect(parseBacklogProjects(['project_name: x', 'projects: [frontend, "nvim-config"]']), ['frontend', 'nvim-config']);
    expect(parseBacklogProjects(['project_name: x']), isEmpty);
  });

  test('tasks come from the .nvimos folder, filtered by project; a toggles all; new tasks land there', () async {
    final (code, plan) = await sharedPlanning();
    final nvim = await TestNvim.start(cwd: code);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final ws = Workspace(s);
    await until(() => ws.loaded);

    expect(ws.tracking!.elsewhere, isTrue);
    expect(ws.project, 'frontend');
    // TASK-2 is nvim-config's; TASK-7 has no project label, so it is shared.
    expect(ws.tasks.map((t) => t.id), ['TASK-1', 'TASK-7']);
    expect(ws.changes.map((c) => c.id), ['ui']);
    expect(ws.absolute('backlog/x.md'), '${plan.path.replaceAll('\\', '/')}/backlog/x.md');

    ws.setProjectOnly(false);
    expect(ws.tasks.map((t) => t.id), ['TASK-1', 'TASK-2', 'TASK-7']);
    expect(ws.changes.length, 2);
    ws.setProjectOnly(true);

    // Numbers are shared across projects; the new task gets the project label.
    final (err, id) = await ws.createTask(title: 'new one');
    expect(err, isNull);
    expect(id, 'TASK-8');
    final file = File('${plan.path}/backlog/tasks/task-8 - new-one.md');
    expect(file.existsSync(), isTrue, reason: 'created in the planning folder');
    expect(await file.readAsString(), contains('frontend'));
    expect(Directory('${code.path}/backlog').existsSync(), isFalse);
    expect(ws.tasks.map((t) => t.id), contains('TASK-8'));

    ws.dispose();
    s.dispose();
    await nvim.stop();
  });
}
