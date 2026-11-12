import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/ui/tasks/tasks_nav.dart';
import 'package:nvimos_poc/ui/tasks/tasks_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'workspace_test.dart' show planRepo;

void main() {
  testWidgets('the mouse wheel scrolls the Tasks sidebar (views, sources, labels)', (t) async {
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
    await t.binding.setSurfaceSize(const Size(1000, 260)); // lower than the sidebar
    await t.pumpWidget(
      SessionScope(
        session: s,
        child: MaterialApp(theme: buildTheme(), home: Scaffold(body: TasksView(key: key, ws: ws))),
      ),
    );
    await t.pump();
    double offset() => t.state<ScrollableState>(find.descendant(of: find.byType(TasksNav), matching: find.byType(Scrollable))).position.pixels;
    expect(offset(), 0);
    final at = t.getCenter(find.text('Inbox').first);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    final middle = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await mouse.addPointer(location: at);
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.pump();
    expect(offset(), greaterThan(0));
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -500)));
    await t.pump();
    expect(offset(), 0);

    // Shift + wheel steps through the entries at any time, and does not scroll.
    String? title() => t.widget<Text>(find.descendant(of: find.byType(TaskListHeader), matching: find.byType(Text)).first).data;
    final first = title();
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump(); // the list stops scrolling while Shift is down
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(offset(), 0);
    expect(title(), isNot(first));
    // Windows may send Shift + wheel as a sideways scroll: still a step, not a scroll.
    final second = title();
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump(); // the list stops scrolling while Shift is down
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(120, 0)));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(offset(), 0);
    expect(title(), isNot(second));

    // A middle click on the Facets makes the wheel step through the entries; it no longer scrolls.
    final before = title();
    await middle.down(at);
    await middle.up();
    await t.pump();
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.pump();
    expect(offset(), 0);
    expect(title(), isNot(before));
    // The local-setup exception: Shift+Insert over the pane is the same toggle (back to scrolling).
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.insert);
    await t.sendKeyUpEvent(LogicalKeyboardKey.insert);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.pump();
    expect(offset(), greaterThan(0));
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -500)));
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.insert);
    await t.sendKeyUpEvent(LogicalKeyboardKey.insert);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump(); // stepping again
    // Another middle click: the wheel scrolls again.
    await middle.down(at);
    await middle.up();
    await t.pump();
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.pump();
    expect(offset(), greaterThan(0));

    // The task list works the same way: a middle click, then the wheel selects the next task.
    await t.tap(find.text('All tasks').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(key.currentState!.pane, TasksPane.nav); // a click in the Facets makes them the active pane
    final row = t.getCenter(find.text('first').first);
    await mouse.moveTo(row);
    await middle.down(row);
    await middle.up();
    await t.pump();
    expect(key.currentState!.pane, TasksPane.list); // and a click on the list makes that the active pane
    await t.sendEventToBinding(PointerScrollEvent(position: row, scrollDelta: const Offset(0, 120)));
    await t.pump(const Duration(milliseconds: 300));
    expect(key.currentState!.selected, isNotNull);
    final selectedFirst = key.currentState!.selected;
    await t.sendEventToBinding(PointerScrollEvent(position: row, scrollDelta: const Offset(0, 120)));
    await t.pump(const Duration(milliseconds: 300));
    expect(key.currentState!.selected, isNot(selectedFirst));
    await mouse.removePointer();

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      ws.dispose();
      s.dispose();
      await nvim.stop();
    });
  });
}
