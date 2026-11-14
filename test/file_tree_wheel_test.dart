import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/file_tree.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  testWidgets('over a file list, Shift + wheel or a middle click then the wheel steps through the files', (t) async {
    final steps = <int>[];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FileTree(
            files: [for (var i = 0; i < 40; i++) TreeFile(path: 'f$i.txt', status: 'modified')],
            selected: 'f0.txt',
            onSelect: (_) {},
            onStep: steps.add,
          ),
        ),
      ),
    );
    final at = t.getCenter(find.text('f0.txt'));
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    final middle = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await mouse.addPointer(location: at);
    double offset() => t.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    // The plain wheel scrolls the list and steps nothing.
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.pump();
    expect(steps, isEmpty);
    expect(offset(), greaterThan(0));
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -500)));
    await t.pump();

    // Shift + wheel steps, down and up, and does not scroll.
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -120)));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(steps, [1, -1]);
    expect(offset(), 0);

    // A middle click switches to stepping; another switches back to scrolling.
    await middle.down(at);
    await middle.up();
    await t.pump();
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.pump();
    expect(steps, [1, -1, 1]);
    expect(offset(), 0);
    await middle.down(at);
    await middle.up();
    await t.pump();
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)));
    await t.pump();
    expect(steps.length, 3);
    expect(offset(), greaterThan(0));
    await mouse.removePointer();
  });
}
