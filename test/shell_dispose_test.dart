import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/mode_rail.dart' show Mode, ModeRail;
import 'package:nvimos_poc/ui/shell.dart';
import 'package:nvimos_poc/ui/tasks/tasks_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'support/local_temp_repo.dart';
import 'support/temp_dirs.dart';

/// A shell over a connected local repo. [Prefs.baseOverride] is a temp folder, so Tasks' own
/// [Prefs.load] never writes the user's state.json.
Future<Session> connected(WidgetTester t) async {
  final prefs = keepForCleanup(await Directory.systemTemp.createTemp('nvimos_prefs_'));
  Prefs.baseOverride = prefs.path;
  addTearDown(() => Prefs.baseOverride = null);
  final repo = await TempRepo.make();
  final s = Session(prefs: Prefs.load());
  addTearDown(s.dispose);
  addTearDown(s.disconnect);
  await s.openFolder(repo.path);
  expect(s.conn, Conn.connected, reason: s.error);
  await t.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(SessionScope(session: s, child: MaterialApp(theme: buildTheme(), home: const Shell())));
  await t.pump();
  return s;
}

ModeRail rail(WidgetTester t) => t.widget<ModeRail>(find.byType(ModeRail));

TasksViewState tasks(WidgetTester t) => t.state<TasksViewState>(find.byType(TasksView, skipOffstage: false));

void main() {
  testWidgets('closing unsubscribes before it disposes, a mode switch does not', (t) async {
    await t.runAsync(() => connected(t));

    rail(t).onSelect(Mode.tasks);
    await t.pump();
    final view = tasks(t);
    expect(view.listening, isTrue, reason: 'Tasks is listening');

    rail(t).onSelect(Mode.changes);
    await t.pump();
    expect(tasks(t), same(view), reason: 'a switch keeps the view');
    expect(view.listening, isTrue, reason: 'the listener stays until close');

    await t.pumpWidget(const SizedBox.shrink());
    expect(find.byType(TasksView, skipOffstage: false), findsNothing);
  });

  testWidgets('closing without opening Tasks is quiet', (t) async {
    await t.runAsync(() => connected(t));
    expect(rail(t).mode, isNot(Mode.tasks));
    await t.pumpWidget(const SizedBox.shrink());
  });
}
