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
