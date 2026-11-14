import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/diff_prefs.dart';
import 'package:nvimos_poc/ui/mode_rail.dart';
import 'package:nvimos_poc/ui/theme.dart';

/// The x of every rail entry's icon, in rail order.
List<double> iconLeft(WidgetTester t) => [
  for (final item in t.widgetList<RailItem>(find.byType(RailItem)))
    t.getTopLeft(find.descendant(of: find.byWidget(item), matching: find.byType(Icon))).dx,
];

/// The left line of every rail entry, in rail order: (colour, width).
List<(Color, double)> lines(WidgetTester t) => [
  for (final item in t.widgetList<RailItem>(find.byType(RailItem)))
    () {
      final box = t.widget<Container>(find.descendant(of: find.byWidget(item), matching: find.byType(Container)));
      final side = ((box.decoration as BoxDecoration).border as Border).left;
      return (side.color, side.width);
    }(),
];

Future<void> pumpRail(WidgetTester t, Mode mode, DiffLayout layout) => t.pumpWidget(
  MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: Row(
        children: [
          ModeRail(mode: mode, expanded: false, layout: layout, onSelect: (_) {}, onToggle: () {}, onLayout: (_) {}),
        ],
      ),
    ),
  ),
);

void main() {
  const clear = Color(0x00000000);

  testWidgets('the mode and both its views are lit with the same line', (t) async {
    await pumpRail(t, Mode.pullRequest, DiffLayout.unified);
    // Order: collapse button, Pull request, Unified, Side by side, Changes, Tasks, Directories, Help.
    expect(lines(t), [
      (clear, 2.0),
      (C.accent, 2.0), // the current mode
      (C.accent, 2.0), // the current view: the same line, indented further instead
      (C.accent, 2.0), // the other view: lit with the mode
      (clear, 2.0),
      (clear, 2.0),
      (clear, 2.0),
      (clear, 2.0),
    ]);

    await pumpRail(t, Mode.pullRequest, DiffLayout.sideBySide);
    expect(lines(t).sublist(1, 4), [(C.accent, 2.0), (C.accent, 2.0), (C.accent, 2.0)]);

    await pumpRail(t, Mode.tasks, DiffLayout.sideBySide); // a mode without views: just its line
    expect(lines(t).where((l) => l.$1 == C.accent).toList(), [(C.accent, 2.0)]);
  });

  testWidgets('the views are indented under their mode, the current view further', (t) async {
    for (final expanded in [false, true]) {
      await t.pumpWidget(const SizedBox()); // a fresh rail starts at its final width
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Row(
              children: [
                ModeRail(
                  mode: Mode.pullRequest,
                  expanded: expanded,
                  layout: DiffLayout.unified,
                  onSelect: (_) {},
                  onToggle: () {},
                  onLayout: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      // Order: collapse button, Pull request, Unified (current), Side by side, Changes, ...
      final x = iconLeft(t);
      final (mode, current, other, next) = (x[1], x[2], x[3], x[4]);
      expect(other, greaterThan(mode), reason: 'a view is indented under its mode (expanded: $expanded)');
      expect(current, greaterThan(other), reason: 'the current view is indented further');
      expect(next, mode, reason: 'the next mode is back in line');
    }
  });

  testWidgets('expanding and collapsing the rail overflows nothing on the way', (t) async {
    Widget rail(bool expanded) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Row(
          children: [
            ModeRail(
              mode: Mode.changes,
              expanded: expanded,
              layout: DiffLayout.sideBySide,
              onSelect: (_) {},
              onToggle: () {},
              onLayout: (_) {},
            ),
          ],
        ),
      ),
    );
    await t.pumpWidget(rail(false));
    await t.pumpWidget(rail(true)); // starts to widen; a layout overflow would fail the test
    await t.pump(const Duration(milliseconds: 40));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Side by side'), findsOneWidget);
    await t.pumpWidget(rail(false));
    await t.pump(const Duration(milliseconds: 40));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Side by side'), findsNothing);
  });

  testWidgets('the mouse wheel over the rail steps to the next or previous mode', (t) async {
    final steps = <int>[];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Row(
            children: [
              ModeRail(
                mode: Mode.tasks,
                expanded: false,
                layout: null,
                onSelect: (_) {},
                onStep: steps.add,
                onToggle: () {},
                onLayout: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    final at = t.getCenter(find.byType(ModeRail));
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 40)));
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -40)));
    expect(steps, [1, -1]); // wheel down: next, wheel up: previous
    await mouse.removePointer();
  });
}
