import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/resizable_pane.dart';

const _content = Key('content');

/// A pane of [autoWidth] in an 800 px wide room, so a drag can make it 280 to 560 px wide.
Future<void> mount(WidgetTester t, {double autoWidth = 400}) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ResizablePane(
        autoWidth: autoWidth,
        minWidth: 280,
        child: const SizedBox.expand(key: _content),
      ),
    ),
  ),
);

double width(WidgetTester t) => t.getSize(find.byKey(_content)).width;

Finder get edge => find.descendant(
  of: find.byType(ResizablePane),
  matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onHorizontalDragUpdate != null),
);

void main() {
  testWidgets('several moves in one frame widen the pane by exactly their sum', (t) async {
    await mount(t);
    expect(width(t), 400);
    final g = await t.startGesture(t.getCenter(edge), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(10, 0)); // no pump between: the events of one frame
    }
    await t.pump();
    expect(width(t), 460, reason: 'every move counts');
    await g.moveBy(const Offset(-25, 0));
    await t.pump();
    expect(width(t), 435);
    await g.up();
    await t.pump(const Duration(milliseconds: 400)); // past the edge's double-tap timer
  });

  testWidgets('past the minimum and back, the edge is under the pointer again', (t) async {
    await mount(t);
    final start = t.getCenter(edge);
    final g = await t.startGesture(start, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(-200, 0));
    await t.pump();
    expect(width(t), 280, reason: 'clamped at the minimum');
    await g.moveBy(const Offset(80, 0)); // still left of where 280 px puts the edge
    await t.pump();
    expect(width(t), 280);
    await g.moveBy(const Offset(60, 0)); // 60 px left of the start
    await t.pump();
    expect(width(t), 340);
    expect(t.getCenter(edge).dx, start.dx - 60, reason: 'the edge is back under the pointer');
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('past the maximum and back, the edge is under the pointer again', (t) async {
    await mount(t);
    final start = t.getCenter(edge);
    final g = await t.startGesture(start, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(300, 0));
    await t.pump();
    expect(width(t), 560, reason: 'clamped at 70% of the room');
    await g.moveBy(const Offset(-250, 0)); // 50 px right of the start
    await t.pump();
    expect(width(t), 450);
    expect(t.getCenter(edge).dx, start.dx + 50);
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a double click on the edge goes back to the natural width', (t) async {
    await mount(t);
    await t.drag(edge, const Offset(50, 0));
    await t.pump(const Duration(milliseconds: 400));
    expect(width(t), greaterThan(400));
    await t.tap(edge);
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(edge);
    await t.pump(const Duration(milliseconds: 400));
    expect(width(t), 400);
  });
}
