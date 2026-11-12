import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/help_view.dart';
import 'package:nvimos_poc/ui/widgets.dart';

import 'help_view_test.dart' show highlighted;

Future<void> altX(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyX);
  await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await t.pump();
}

void main() {
  testWidgets('Alt+X in a filter field empties it and tells the list, so the filtering resets', (t) async {
    final c = TextEditingController(text: 'abc');
    final told = <String>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClearOnAltX(controller: c, onCleared: told.add, child: TextField(controller: c)),
        ),
      ),
    );
    await t.tap(find.byType(TextField));
    await t.pump();
    await altX(t);
    expect(c.text, '');
    expect(told, ['']);
    c.dispose();
  });

  testWidgets('Alt+X in the Help search removes the highlights', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));
    await t.tap(find.byType(TextField));
    await t.enterText(find.byType(TextField), 'stage');
    await t.pump();
    expect(highlighted(t), greaterThan(0));
    await altX(t);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(highlighted(t), 0);
  });
}
