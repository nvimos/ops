import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/ui/tasks/tasks_nav.dart';
import 'package:nvimos_poc/ui/tasks/tasks_view.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'package:nvimos_poc/ui/widgets.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'workspace_test.dart' show planRepo;

/// Clicks through every Tasks screen on a real planning repo; a guard for UI refactors.
/// Neovim and the workspace run in real time (runAsync); the widgets on the test clock.
void main() {
  tasksPaneTest();
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

    // Labels: collapsed at first, with their count; the chevron opens the list.
    expect(find.byIcon(Icons.label_outline), findsNothing);
    expect(find.textContaining('LABELS', findRichText: true), findsOneWidget);
    await t.tap(find.byIcon(Icons.chevron_right));
    await t.pump();
    expect(find.byIcon(Icons.label_outline), findsOneWidget); // TASK-1's label "a"

    await tap('All tasks');
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    await tap('first');
    expect(find.text('TASK-1'), findsWidgets); // the detail panel's kicker
    expect(find.text('try it'), findsWidgets); // its Verify step

    // Widen: the panel doubles over the list (the list keeps its width), and narrows again.
    double panelWidth() => t.getSize(find.byType(DetailPanel)).width;
    Future<void> settle() async {
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
    }

    await settle();
    final normal = panelWidth();
    final listWidth = t.getSize(find.byType(TaskListHeader)).width;
    await t.tap(find.byIcon(Icons.open_in_full));
    await settle();
    expect(panelWidth(), closeTo(normal * 2, 1));
    expect(t.getSize(find.byType(TaskListHeader)).width, listWidth);
    await t.tap(find.byIcon(Icons.close_fullscreen));
    await settle();
    expect(panelWidth(), closeTo(normal, 1));

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

    // The x in the field clears it, and every row is back.
    await t.tap(find.descendant(of: find.byType(ClearButton), matching: find.byIcon(Icons.close)));
    await t.pump();
    expect(find.text('first'), findsOneWidget);
    expect(find.descendant(of: find.byType(ClearButton), matching: find.byIcon(Icons.close)), findsNothing);

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      ws.dispose();
      s.dispose();
      await nvim.stop();
    });
  });
}

/// The panes of the Tasks mode: the sidebar, the list and the detail, and the keys between them.
void tasksPaneTest() {
  testWidgets('Left and Right visit the sidebar, the list and the detail; wasd works like the arrows', (t) async {
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
    var rail = 0;
    await t.binding.setSurfaceSize(const Size(1400, 900));
    await t.pumpWidget(
      SessionScope(
        session: s,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: TasksView(key: key, ws: ws, onRail: () => rail++)),
        ),
      ),
    );
    await t.pump();
    key.currentState!.focus.requestFocus();
    await t.pump();
    final tasks = key.currentState!;

    Future<void> press(LogicalKeyboardKey k, {String? ch}) async {
      await t.sendKeyEvent(k, character: ch);
      await t.pump(const Duration(milliseconds: 250));
    }

    expect(tasks.pane, TasksPane.list);
    await press(LogicalKeyboardKey.arrowLeft); // the list: the sidebar is to its left
    expect(tasks.pane, TasksPane.nav);

    final before = tasks.browser.view;
    await press(LogicalKeyboardKey.keyS, ch: 's'); // down in the sidebar: the next entry
    expect(tasks.browser.view, isNot(before));
    await press(LogicalKeyboardKey.keyW, ch: 'w'); // and back up
    expect(tasks.browser.view, before);

    await press(LogicalKeyboardKey.arrowRight);
    expect(tasks.pane, TasksPane.list);
    await press(LogicalKeyboardKey.keyD, ch: 'd'); // right from the list: the current task's detail
    expect(tasks.pane, TasksPane.detail);
    expect(tasks.browser.selected, isNotNull);

    // Left moves from element to element in the detail; past the leftmost one it is the list again.
    for (var i = 0; i < 30 && tasks.pane == TasksPane.detail; i++) {
      await press(LogicalKeyboardKey.keyA, ch: 'a');
    }
    expect(tasks.pane, TasksPane.list);
    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.keyH, ch: 'h');
    expect(rail, 1); // left from the sidebar: the rail

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      s.dispose();
      await nvim.stop();
    });
  });
}
