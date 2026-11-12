import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/tasks/markdown.dart';
import 'package:nvimos_poc/ui/tasks/rich.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  Future<List<bool>> clicks(WidgetTester t, Future<void> Function(Finder text) act, {String mark = ' '}) async {
    final got = <bool>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CheckRow(Check(0, mark == 'x', 'write it', 0, mark: mark), onCheck: got.add),
        ),
      ),
    );
    await act(find.text('write it'));
    return got;
  }

  testWidgets('a click on the text toggles; Ctrl+click and right click cycle', (t) async {
    expect(await clicks(t, (f) => t.tap(f)), [false]);
    expect(await clicks(t, (f) => t.tap(f, buttons: kSecondaryButton)), [true]);
    expect(
      await clicks(t, (f) async {
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.tap(f);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }),
      [true],
    );
  });

  testWidgets('the row shows the pointer cursor; every mark has its own icon', (t) async {
    await clicks(t, (f) async {});
    final region = t.widget<MouseRegion>(find.descendant(of: find.byType(CheckRow), matching: find.byType(MouseRegion)).first);
    expect(region.cursor, SystemMouseCursors.click);

    Color? back() => (t.widget<Container>(find.descendant(of: find.byType(CheckRow), matching: find.byType(Container)).first).decoration as BoxDecoration).color;
    expect(back(), Colors.transparent);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: t.getCenter(find.text('write it')));
    await t.pump();
    expect(back(), C.hover); // lit like the other rows of a list
    await mouse.removePointer();
    for (final m in [' ', 'x', '.', '~', 'n']) {
      await t.pumpWidget(MaterialApp(home: CheckMark(m)));
      expect(find.byType(Icon), findsWidgets, reason: m);
    }
  });
}
