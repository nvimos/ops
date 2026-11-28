import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/ui/tasks/rows.dart';
import 'package:nvimos_poc/ui/tasks/tasks_nav.dart';
import 'package:nvimos_poc/ui/tasks/tasks_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'timing_measure_test.dart' show bigPlanRepo;

/// Prints how long a cursor move in the Tasks list takes, key press to painted frame
/// (`flutter test test/tasks_move_timing_test.dart`); `TASKS_REPO=<path>` measures a real repo.
/// Asserts only that a cursor move keeps the rows and the sidebar counts (no recompute).
void main() {
  testWidgets('timings of Tasks cursor moves', (t) async {
    final (nvim, s, ws) = (await t.runAsync(() async {
      final real = Platform.environment['TASKS_REPO'];
      final repo = real != null ? Directory(real) : await bigPlanRepo(62);
      final nvim = await TestNvim.start(cwd: repo);
      await nvim.connect().then((r) => r.close());
      final s = Session(port: nvim.port);
      await s.connect();
      final ws = Workspace(s);
      await until(() => ws.loaded && !ws.loading, timeout: const Duration(seconds: 20));
      return (nvim, s, ws);
    }))!;
    final key = GlobalKey<TasksViewState>();
    await t.binding.setSurfaceSize(const Size(1400, 900));
    await t.pumpWidget(
      SessionScope(
        session: s,
        child: MaterialApp(theme: buildTheme(), home: Scaffold(body: TasksView(key: key, ws: ws))),
      ),
    );
    await t.pump();
    await t.tap(find.textContaining('All tasks', findRichText: true).first);
    await t.pump(const Duration(milliseconds: 300));
    key.currentState!.focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // the click left the keys in the sidebar
    await t.pump();

    double p50(List<double> xs) => (xs..sort())[xs.length ~/ 2];
    Future<List<double>> frames(int n, Future<void> Function() input) async {
      final ms = <double>[];
      for (var i = 0; i < n; i++) {
        final sw = Stopwatch()..start();
        await input();
        await t.pump();
        ms.add(sw.elapsedMicroseconds / 1000);
      }
      return ms;
    }

    final b = key.currentState!.browser;
    final rows = b.rows(), tasks = b.navTasks(), labels = b.navLabels(), sources = b.navSources();
    final inboxCount = b.inboxCount;
    final moves = await frames(20, () => t.sendKeyEvent(LogicalKeyboardKey.keyJ));
    final same = await frames(10, () async => b.select(b.selected)); // the rebuild alone, no new detail
    expect(identical(b.rows(), rows), isTrue, reason: 'a cursor move keeps the rows');
    expect(identical(b.navTasks(), tasks) && identical(b.navLabels(), labels) && identical(b.navSources(), sources), isTrue,
        reason: 'a cursor move keeps the sidebar entries');
    expect(b.inboxCount, inboxCount);

    // A cursor move rebuilds the rows' highlight and the detail, not the sidebar or the row contents.
    final built = <Type, int>{};
    debugOnRebuildDirtyWidget = (e, _) => built.update(e.widget.runtimeType, (n) => n + 1, ifAbsent: () => 1);
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.pump();
    debugOnRebuildDirtyWidget = null;
    expect([built[TasksNav], built[TaskListHeader], built[TaskRow]], [null, null, null],
        reason: 'rebuilt on a cursor move: $built');

    double each(void Function() f) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        f();
      }
      return sw.elapsedMicroseconds / 10000;
    }

    final task = ws.tasks.first;
    // ignore: avoid_print
    print('tasks ${ws.tasks.length}: j move p50 ${p50(moves)} max ${moves.last} ms; same-selection rebuild p50 '
        '${p50(same)} ms; per call ms: inboxCount ${each(() => b.inboxCount)}, navLabels ${each(b.navLabels)}, '
        'changeFor ${each(() => ws.changeFor(task))}, branchFor ${each(() => ws.branchFor(task))}');

    await t.runAsync(() async {
      ws.dispose();
      s.dispose();
      await nvim.stop();
    });
  }, timeout: const Timeout(Duration(seconds: 90)));
}
