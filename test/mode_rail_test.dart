import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/diff_prefs.dart';
import 'package:nvimos_poc/ui/mode_rail.dart';
import 'package:nvimos_poc/ui/theme.dart';

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
          ModeRail(
            mode: mode,
            expanded: false,
            layout: layout,
            onSelect: (_) {},
            onToggle: () {},
            onLayout: (_) {},
          ),
        ],
      ),
    ),
  ),
);

void main() {
  const clear = Color(0x00000000);

  testWidgets('the mode and both its views are lit; the current view has a line twice as wide', (t) async {
    await pumpRail(t, Mode.pullRequest, DiffLayout.unified);
    // Order: collapse button, Pull request, Unified, Side by side, Changes, Tasks, Directories, Help.
    expect(lines(t), [
      (clear, 2.0),
      (C.accent, 2.0), // the current mode
      (C.accent, 4.0), // the current view: twice as wide
      (C.accent, 2.0), // the other view: lit with the mode
      (clear, 2.0),
      (clear, 2.0),
      (clear, 2.0),
      (clear, 2.0),
    ]);

    await pumpRail(t, Mode.pullRequest, DiffLayout.sideBySide);
    expect(lines(t).sublist(1, 4), [(C.accent, 2.0), (C.accent, 2.0), (C.accent, 4.0)]);

    await pumpRail(t, Mode.tasks, DiffLayout.sideBySide); // a mode without views: just its line
    expect(lines(t).where((l) => l.$1 == C.accent).toList(), [(C.accent, 2.0)]);
  });
}
