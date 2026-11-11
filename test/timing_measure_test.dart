import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/timing/ui_timing.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

/// A planning repo the size of a busy project: [n] tasks with checklists, n/5 changes.
Future<Directory> bigPlanRepo(int n) async {
  final d = await makeRepo();
  Future<void> w(String p, String s) async {
    await File('${d.path}/$p').create(recursive: true);
    await File('${d.path}/$p').writeAsString(s);
  }

  await w('backlog/config.yml', 'project_name: "big"\nstatuses: ["To Do", "In Progress", "Done"]\n');
  for (var i = 1; i <= n; i++) {
    final checks = List.generate(8, (j) => '- [ ] #${j + 1} check $j of task $i').join('\n');
    final body = List.generate(20, (j) => 'Line $j of the description of task $i, with some words.').join('\n');
    await w(
      'backlog/tasks/task-$i - t$i.md',
      '---\nid: TASK-$i\ntitle: task $i\nstatus: To Do\nlabels: [a, b]\n---\n\n## Description\n\n$body\n\n'
          '## Acceptance Criteria\n\n$checks\n\n## Verify\n\n$checks\n',
    );
    if (i % 5 == 0) {
      await w('openspec/changes/$i-c/proposal.md', '# $i. c\n\nStatus: To Do (backlog TASK-$i)\n\n## Why\n\n$body\n');
      await w('openspec/changes/$i-c/tasks.md', '# Tasks\n\n## 1. Build\n\n$checks\n');
    }
  }
  await git(d, ['add', '.']);
  await git(d, ['commit', '-q', '-m', 'plan']);
  return d;
}

/// Not a check: prints where the time of a Tasks checkbox click goes (`flutter test
/// test/timing_measure_test.dart`). Asserts only that a check never flips back after a click.
void main() {
  test('timings of Tasks checkbox clicks in a 300-task repo', () async {
    final repo = await bigPlanRepo(300);
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final ws = Workspace(s);
    await until(() => ws.loaded && !ws.loading, timeout: const Duration(seconds: 20));
    UiTiming.instance.samples.clear();

    // Click checks of one task, one after the other like a user would; watch every state the
    // UI is told about.
    final flips = <String>[];
    for (var k = 0; k < 6; k++) {
      final t = ws.task('TASK-150')!;
      final c = t.verify[k];
      void watch() {
        final now = ws.task('TASK-150')?.verify[k].done;
        if (now == c.done) flips.add('check $k showed unchecked again');
      }

      await ws.toggleCheck(t.path, c);
      ws.addListener(watch);
      await Future<void>.delayed(const Duration(milliseconds: 600)); // the reload the write sets off
      ws.removeListener(watch);
      if (ws.task('TASK-150')!.verify[k].done != true) flips.add('check $k unchecked after 600 ms');
    }
    await until(() => !ws.loading);
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(UiTiming.instance.summary()['actions']));
    expect(flips, isEmpty);

    ws.dispose();
    s.dispose();
    await nvim.stop();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
