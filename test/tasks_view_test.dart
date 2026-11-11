import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/ui/tasks/tasks_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'workspace_test.dart' show planRepo;

/// Clicks through every Tasks screen on a real planning repo; a guard for UI refactors.
/// Neovim and the workspace run in real time (runAsync); the widgets on the test clock.
void main() {
  testWidgets('sidebar views, list rows, detail panels and keys', (t) async {
    final (nvim, s, ws) = (await t.runAsync(() async {
      final repo = await planRepo();
      final nvim = await TestNvim.start(cwd: repo);
      await nvim.connect().then((r) => r.close());
      final s = Session(port: nvim.port);
      await s.connect();
      final ws = Workspace(s);
      await until(() => ws.loaded);
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

    Future<void> tap(String text) async {
      await t.tap(find.textContaining(text, findRichText: true).first);
      await t.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('demo'), findsOneWidget); // project name from backlog/config.yml

    await tap('All tasks');
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    await tap('first');
    expect(find.text('TASK-1'), findsWidgets); // the detail panel's kicker
    expect(find.text('try it'), findsWidgets); // its Verify step

    // Keys: j moves to the next task, Esc closes the panel.
    key.currentState!.focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.pump(const Duration(milliseconds: 300));
    expect(key.currentState!.selected, 'TASK-2');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 300));
    expect(key.currentState!.selected, isNull);

    await tap('Changes');
    expect(find.textContaining('first'), findsWidgets);
    await tap('Legacy notes');
    expect(find.textContaining('old thing'), findsWidgets);
    await tap('old thing');
    expect(find.text('legacy/todo-2027.md'), findsOneWidget);
    await tap('Specs');
    await tap('Milestones');
    expect(find.text('milestone'), findsNothing);

    // Filter: only matching rows stay.
    await tap('All tasks');
    await t.enterText(find.byType(TextField).first, 'second');
    await t.pump();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsNWidgets(2)); // the row and the filter field

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      ws.dispose();
      s.dispose();
      await nvim.stop();
    });
  });
}
