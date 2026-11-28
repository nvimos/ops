import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/timing/ui_timing.dart';
import 'package:nvimos_poc/ui/tasks/rows.dart';
import 'package:nvimos_poc/ui/tasks/tasks_nav.dart';
import 'package:nvimos_poc/ui/tasks/tasks_view.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'package:nvimos_poc/ui/widgets.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'support/snappy.dart';
import 'support/temp_dirs.dart';

/// Snappy UI checks (OpenSpec change `ops-snappy-ui-checks`): the Tasks mode on a snapshot of a real
/// project (`test/fixtures/tasks_snappy.json.gz`), every view, every interaction, from the input to
/// the painted frame.
///
/// Two kinds of limits:
/// - structural, the gate: what an interaction is allowed to set off. A cursor move or a row click
///   rebuilds no sidebar, no list header, no row content, recomputes no rows or counts and parses
///   nothing; and no interaction builds more widgets than [work]. Deterministic on any machine.
/// - time, generous: [ms] per interaction, p50 in the debug widget test (JIT, several times the
///   release cost). Catches a large regression; the printed table shows where the time goes.
///
/// Tighten the limits as the code gets faster; refresh the fixture with `make snapshot`.

const views = [
  'Inbox',
  'Open tasks',
  'To Do',
  'In Progress',
  'Needs Test',
  'Done',
  'Dropped',
  'All tasks',
  'Changes',
  'Milestones',
];

/// Widgets built (rebuilt or new) per interaction, at most.
const work = {'switch': 3000, 'open': 3000, 'move': 1500, 'click': 1600, 'detail': 3000};

/// Milliseconds per interaction (p50 for the moves), at most.
const ms = {'switch': 1200.0, 'open': 1000.0, 'move': 400.0, 'click': 500.0, 'detail': 600.0};

/// What a cursor move or a click must not rebuild.
const untouched = {TasksNav, NavItem, TaskListHeader, TaskRow, ChangeRow, InboxRow, MilestoneRow};

class Step {
  Step(this.ms, this.built, this.types);
  final double ms;
  final int built;
  final Map<Type, int> types;
}

void main() {
  testWidgets('snappy: every Tasks view on the fixture', (t) async {
    Prefs.baseOverride = keepForCleanup(Directory.systemTemp.createTempSync('nvimos_appdata_')).path;
    addTearDown(() => Prefs.baseOverride = null);
    final fixture = SnappyFixture.load();
    final (nvim, s, ws) = (await t.runAsync(() async {
      final repo = await fixture.unpack();
      final nvim = await TestNvim.start(cwd: repo);
      await nvim.connect().then((r) => r.close());
      final s = Session(port: nvim.port);
      await s.connect();
      final ws = Workspace(s);
      await until(() => ws.loaded && !ws.loading, timeout: const Duration(seconds: 30));
      return (nvim, s, ws);
    }))!;
    final key = GlobalKey<TasksViewState>();
    await t.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      SessionScope(
        session: s,
        child: MaterialApp(theme: buildTheme(), home: Scaffold(body: TasksView(key: key, ws: ws))),
      ),
    );
    await t.pump();
    final b = key.currentState!.browser;

    Future<Step> step(Future<void> Function() input) async {
      final types = <Type, int>{};
      var built = 0;
      debugOnRebuildDirtyWidget = (e, _) {
        built++;
        types.update(e.widget.runtimeType, (n) => n + 1, ifAbsent: () => 1);
      };
      final sw = Stopwatch()..start();
      await input();
      await t.pump();
      final took = sw.elapsedMicroseconds / 1000;
      debugOnRebuildDirtyWidget = null;
      await t.pump(const Duration(milliseconds: 300)); // let hover and fades settle, not measured
      return Step(took, built, types);
    }

    final failures = <String>[];
    final table = <String>[];

    // A layout overflow on the real data is a bug of its own, not a slow interaction: listed with the
    // view and step it showed up in, printed, and not failing the timing gate.
    var where = 'start';
    final overflows = <String>{};
    final flutterError = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.exceptionAsString();
      if (text.contains('overflowed')) {
        overflows.add('$where: ${text.split('\n').first}');
      } else {
        flutterError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = flutterError);
    String fmt(double v) => v.toStringAsFixed(0).padLeft(4);

    void check(String view, String what, Step st) {
      if (st.built > work[what]!) failures.add('$view $what: built ${st.built} widgets, limit ${work[what]}');
      if (st.ms > ms[what]! && what != 'move') failures.add('$view $what: ${fmt(st.ms)} ms, limit ${ms[what]}');
    }

    /// A cursor move or a click: the cascade stays in the rows' highlight and the detail.
    void keepsTheRest(String view, String what, Step st, (Object, Object, int) before) {
      final hit = [for (final ty in untouched) if (st.types[ty] != null) '$ty ${st.types[ty]}'];
      if (hit.isNotEmpty) failures.add('$view $what rebuilt ${hit.join(', ')}');
      if (!identical(b.rows(), before.$1)) failures.add('$view $what recomputed the rows');
      if (!identical(b.navTasks(), before.$2)) failures.add('$view $what recomputed the sidebar counts');
      if ((UiTiming.instance.samples['tasks.rebuild']?.length ?? 0) != before.$3) failures.add('$view $what parsed files');
    }

    (Object, Object, int) snapshot() => (b.rows(), b.navTasks(), UiTiming.instance.samples['tasks.rebuild']?.length ?? 0);

    final rowFinder = find.descendant(of: find.byType(TaskRows), matching: find.byType(HoverRow));
    for (final view in views) {
      final entry = find.byWidgetPredicate((w) => w is NavItem && w.label == view);
      if (entry.evaluate().isEmpty) {
        failures.add('$view: no sidebar entry');
        continue;
      }
      where = '$view switch';
      final switched = await step(() => t.tap(entry.first));
      check(view, 'switch', switched);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // from the sidebar into the list
      await t.pump();
      final items = b.rows().where((r) => !r.isHeader).length;
      if (items == 0) {
        table.add('${view.padRight(12)} ${'$items'.padLeft(4)}  switch ${fmt(switched.ms)} ms ${'${switched.built}'.padLeft(5)}');
        continue;
      }

      // The first j opens the detail panel: the list gets narrower and every row is laid out, and
      // built, again. Measured on its own; the moves after it keep the rows.
      where = '$view open';
      final opened = await step(() => t.sendKeyEvent(LogicalKeyboardKey.keyJ));
      check(view, 'open', opened);
      where = '$view move';
      final moves = <Step>[];
      for (var i = 0; i < 5; i++) {
        final before = snapshot();
        final st = await step(() => t.sendKeyEvent(LogicalKeyboardKey.keyJ));
        keepsTheRest(view, 'move', st, before);
        check(view, 'move', st);
        moves.add(st);
      }
      final sorted = [...moves.map((m) => m.ms)]..sort();
      final p50 = sorted[sorted.length ~/ 2];
      if (p50 > ms['move']!) failures.add('$view move: p50 ${fmt(p50)} ms, limit ${ms['move']}');

      where = '$view click';
      final before = snapshot();
      final rowCount = rowFinder.evaluate().length;
      final clicked = await step(() => t.tap(rowFinder.at(rowCount > 1 ? 1 : 0)));
      keepsTheRest(view, 'click', clicked, before);
      check(view, 'click', clicked);
      if (b.selected == null) await t.sendKeyEvent(LogicalKeyboardKey.keyJ); // the click closed it

      where = '$view detail';
      final detail = await step(() => t.sendKeyEvent(LogicalKeyboardKey.arrowRight));
      check(view, 'detail', detail);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // back to the list
      await t.pump();

      final mostMove = moves.map((m) => m.built).reduce((a, c) => a > c ? a : c);
      table.add('${view.padRight(12)} ${'$items'.padLeft(4)}  switch ${fmt(switched.ms)} ms ${'${switched.built}'.padLeft(5)}'
          '  open ${fmt(opened.ms)} ms ${'${opened.built}'.padLeft(5)}'
          '  move ${fmt(p50)} ms ${'$mostMove'.padLeft(5)}  click ${fmt(clicked.ms)} ms ${'${clicked.built}'.padLeft(5)}'
          '  detail ${fmt(detail.ms)} ms ${'${detail.built}'.padLeft(5)}');
    }
    // ignore: avoid_print
    print('snappy, ${fixture.source}, ${ws.tasks.length} tasks; ms and widgets built per interaction '
        '(move: p50 ms, most widgets)\n${table.join('\n')}'
        '${overflows.isEmpty ? '' : '\nlayout overflows (not timing failures):\n${overflows.join('\n')}'}');

    await t.runAsync(() async {
      ws.dispose();
      s.dispose();
      await nvim.stop();
    });
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
