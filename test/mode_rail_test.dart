import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/diff_prefs.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/ui/mode_rail.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'package:nvimos_poc/ui/view_bar.dart';

/// The left line of every rail entry, in rail order: (colour, width).
List<(Color, double)> lines(WidgetTester t) => [
  for (final item in t.widgetList<RailItem>(find.byType(RailItem)))
    () {
      final box = t.widget<Container>(find.descendant(of: find.byWidget(item), matching: find.byType(Container)));
      final side = ((box.decoration as BoxDecoration).border as Border).left;
      return (side.color, side.width);
    }(),
];

Widget rail(Mode mode, {bool expanded = false, ValueChanged<int>? onStep}) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(
    body: Row(
      children: [ModeRail(mode: mode, expanded: expanded, onSelect: (_) {}, onStep: onStep, onToggle: () {})],
    ),
  ),
);

void main() {
  const clear = Color(0x00000000);

  testWidgets('the rail has one plain icon per mode and no sub entries; only the current mode is lit', (t) async {
    await t.pumpWidget(rail(Mode.pullRequest));
    // Order: collapse button, then the nine modes.
    expect(lines(t), [
      (clear, 2.0),
      (C.accent, 2.0),
      for (var i = 0; i < 8; i++) (clear, 2.0),
    ]);
    expect(find.byType(Icon), findsNWidgets(10), reason: 'one icon each, nothing cut or added');
  });

  testWidgets('expanding and collapsing the rail overflows nothing on the way', (t) async {
    await t.pumpWidget(rail(Mode.changes));
    await t.pumpWidget(rail(Mode.changes, expanded: true)); // an overflow would fail the test
    await t.pump(const Duration(milliseconds: 40));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Changes'), findsOneWidget);
    await t.pumpWidget(rail(Mode.changes));
    await t.pump(const Duration(milliseconds: 40));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Changes'), findsNothing);
  });

  testWidgets('the rail snaps to its new width in one frame; the mode area is not relaid per frame', (t) async {
    await t.pumpWidget(rail(Mode.changes));
    expect(t.getSize(find.byType(ModeRail)).width, ModeRail.collapsedWidth);
    await t.pumpWidget(rail(Mode.changes, expanded: true));
    expect(t.getSize(find.byType(ModeRail)).width, ModeRail.expandedWidth, reason: 'no width animation');
    await t.pumpWidget(rail(Mode.changes));
    expect(t.getSize(find.byType(ModeRail)).width, ModeRail.collapsedWidth);
  });

  testWidgets('the mouse wheel over the rail steps to the next or previous mode', (t) async {
    final steps = <int>[];
    await t.pumpWidget(rail(Mode.tasks, onStep: steps.add));
    final at = t.getCenter(find.byType(ModeRail));
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 40)));
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -40)));
    expect(steps, [1, -1]); // wheel down: next, wheel up: previous
    await mouse.removePointer();
  });

  testWidgets('the view bar has a button for each view; Merge works only while a merge is open', (t) async {
    final picked = <DiffLayout>[];
    Future<void> bar(DiffLayout layout, {required bool mergeOpen}) => t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: ViewBar(layout: layout, mergeOpen: mergeOpen, onLayout: picked.add)),
      ),
    );

    await bar(DiffLayout.unified, mergeOpen: false);
    expect(find.text('Unified'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    await t.tap(find.text('Split'));
    await t.tap(find.text('Merge'));
    expect(picked, [DiffLayout.sideBySide], reason: 'Merge is dimmed without a merge in progress');

    await bar(DiffLayout.sideBySide, mergeOpen: true);
    await t.tap(find.text('Merge'));
    await t.tap(find.text('Unified'));
    expect(picked, [DiffLayout.sideBySide, DiffLayout.conflict, DiffLayout.unified]);
  });

  test('the rail order and hidden modes are kept in prefs', () {
    final prefs = Prefs.memory();
    final rail = RailState(prefs);
    rail.reorderVisible(0, 8); // Pull request to the end
    expect(rail.visible.last, Mode.pullRequest);
    expect(rail.hide(Mode.help), isTrue);
    expect(rail.visible, isNot(contains(Mode.help)));
    expect(rail.order.last, Mode.pullRequest, reason: 'the hidden mode keeps its slot');

    rail.show(Mode.help);
    expect(rail.visible, contains(Mode.help));
    expect(rail.visible.last, Mode.pullRequest, reason: 'shown again where it was dragged');

    final again = RailState(prefs);
    expect(again.visible, rail.visible, reason: 'the order and the hidden set are saved');

    for (final m in Mode.values.take(Mode.values.length - 1)) {
      rail.hide(m);
    }
    expect(rail.visible, hasLength(1));
    expect(rail.hide(rail.visible.single), isFalse, reason: 'the app always has a mode');
  });

  test('saved names that no longer exist are dropped and never crash', () {
    final prefs = Prefs.memory();
    prefs.setStrings(RailState.orderKey, ['gone', 'pullRequest', 'changes', 'pullRequest', 'alsoGone']);
    prefs.setStrings(RailState.hiddenKey, ['gone', 'changes', 'changes']);
    final rail = RailState(prefs);

    expect(rail.order.length, Mode.values.length);
    expect(rail.order.toSet(), Mode.values.toSet());
    expect(rail.order.where((m) => m == Mode.pullRequest), hasLength(1), reason: 'no duplicates');
    expect(rail.visible, isNot(contains(Mode.changes)));
    expect(rail.hidden, {Mode.changes});
    // The repaired state is written back, so the next start is clean too.
    expect(prefs.strings(RailState.orderKey), [for (final m in rail.order) m.name]);
    expect(prefs.strings(RailState.hiddenKey), [Mode.changes.name]);
  });

  test('a hidden set that covers every mode is forgotten, and a new mode is visible', () {
    final prefs = Prefs.memory();
    prefs.setStrings(RailState.hiddenKey, [for (final m in Mode.values) m.name, 'gone']);
    final rail = RailState(prefs);

    expect(rail.hidden, isEmpty, reason: 'the app must keep a mode to show');
    expect(rail.visible, Mode.values);
    expect(prefs.strings(RailState.hiddenKey), isEmpty);
  });

  test('a missing mode is appended after a rename in the saved order', () {
    final prefs = Prefs.memory();
    prefs.setStrings(RailState.orderKey, [
      for (final m in Mode.values)
        if (m != Mode.help) m.name,
      'helpp', // the old name: no longer a mode
    ]);
    final rail = RailState(prefs);

    expect(rail.order.last, Mode.help);
    expect(rail.visible, contains(Mode.help));
    expect(prefs.strings(RailState.orderKey), [for (final m in Mode.values) m.name]);
  });

  testWidgets('a dragged icon lands where the drop line shows, going down and going up', (t) async {
    final state = RailState(Prefs.memory());
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (context, _) => Row(
              children: [
                ModeRail(
                  mode: Mode.pullRequest,
                  modes: state.visible,
                  expanded: false,
                  onSelect: (_) {},
                  onToggle: () {},
                  onReorder: state.reorderVisible,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void> drag(Mode from, Mode onto) async {
      final g = await t.startGesture(t.getCenter(find.byIcon(from.icon)));
      await g.moveBy(const Offset(0, 20));
      await t.pump();
      await g.moveTo(t.getCenter(find.byIcon(onto.icon)));
      await t.pump();
      // The line is on the side the mode will land: below the target going down, above going up.
      Border? lineOf(Widget w) =>
          w is DecoratedBox && w.decoration is BoxDecoration ? (w.decoration as BoxDecoration).border as Border? : null;
      final target = find.ancestor(
        of: find.byIcon(onto.icon),
        matching: find.byWidgetPredicate((w) => lineOf(w)?.left == BorderSide.none),
      );
      final border = lineOf(t.widget(target.first))!;
      final down = state.visible.indexOf(from) < state.visible.indexOf(onto);
      expect((down ? border.bottom : border.top).color, C.accent);
      expect((down ? border.top : border.bottom).color, clear);
      await g.up();
      await t.pump();
    }

    final [a, b, c, d, ...] = state.visible;
    await drag(a, c);
    expect(state.visible.take(4), [b, c, a, d], reason: 'down: below the target');
    await drag(d, c);
    expect(state.visible.take(4), [b, d, c, a], reason: 'up: above the target');
  });

  test('order, hidden and visible are cached until the saved state changes, and read-only', () {
    final rail = RailState(Prefs.memory());
    final order = rail.order, visible = rail.visible, hidden = rail.hidden;
    expect(identical(rail.order, order), isTrue, reason: 'no change: the same list');
    expect(identical(rail.visible, visible), isTrue);
    expect(identical(rail.hidden, hidden), isTrue);
    expect(() => rail.visible.add(Mode.help), throwsUnsupportedError);
    expect(() => rail.hidden.add(Mode.help), throwsUnsupportedError);

    rail.hide(Mode.help);
    expect(identical(rail.order, order), isFalse, reason: 'a hide drops the cache');
    expect(identical(rail.visible, visible), isFalse);
    expect(rail.visible, isNot(contains(Mode.help)));
    final afterHide = rail.visible;
    rail.reorderVisible(0, 1);
    expect(identical(rail.visible, afterHide), isFalse, reason: 'a reorder drops it too');
  });

  test('reset restores the default order and shows every mode', () {
    final rail = RailState(Prefs.memory());
    rail.reorderVisible(0, 8);
    rail.hide(Mode.help);
    expect(rail.hidden, isNotEmpty);

    rail.reset();
    expect(rail.order, Mode.values);
    expect(rail.visible, Mode.values);
    expect(rail.hidden, isEmpty);
  });

  test('a reorder with stale indices does nothing', () {
    final rail = RailState(Prefs.memory());
    final before = rail.visible;
    rail.reorderVisible(-1, 2);
    rail.reorderVisible(0, 99);
    expect(rail.visible, before);
  });

  test('a mode cannot hide the last visible one, and a shown mode comes back where it was', () {
    final rail = RailState(Prefs.memory());
    for (final m in Mode.values) {
      rail.hide(m);
    }
    expect(rail.visible, hasLength(1));
    expect(rail.hide(rail.visible.single), isFalse);
    rail.show(Mode.help);
    expect(rail.visible, contains(Mode.help));
  });

  test('cycleLayout goes unified, side by side, merge when one is open, then unified', () {
    final prefs = DiffPrefs(Prefs.memory());
    final steps = <DiffLayout>[];
    for (var i = 0; i < 3; i++) {
      prefs.cycleLayout(conflict: true);
      steps.add(prefs.layout);
    }
    expect(steps, [DiffLayout.sideBySide, DiffLayout.conflict, DiffLayout.unified]);

    // The merge step is skipped without a merge in progress.
    prefs.cycleLayout(conflict: false);
    prefs.cycleLayout(conflict: false);
    expect(prefs.layout, DiffLayout.unified);
  });
}
