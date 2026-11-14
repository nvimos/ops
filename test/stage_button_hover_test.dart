import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/changes_view.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'package:nvimos_poc/ui/widgets.dart';

Widget row({required bool staged}) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        height: 40, // a short row: the rest of the screen is outside it
        child: HoverRow(
          onTap: () {},
          child: Row(children: [const Expanded(child: Text('file.txt')), StageCheckbox(staged: staged, onTap: () {})]),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the add button shows only while the mouse is over its row; the staged box always', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows; // the test default is Android
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await t.pumpWidget(row(staged: false));
    expect(find.text('add'), findsNothing);

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.text('file.txt')));
    await t.pump();
    await t.pump();
    expect(find.text('add'), findsOneWidget);

    await mouse.moveTo(const Offset(5, 590)); // below the row
    await t.pump();
    await t.pump(); // the exit is noticed after the frame; the rebuild comes with the next one
    expect(find.text('add'), findsNothing);
    await mouse.removePointer();

    await t.pumpWidget(row(staged: true));
    expect(find.byIcon(Icons.check_box), findsOneWidget); // staged: always there
  });

  testWidgets('without a mouse (a phone) the add button is always shown', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await t.pumpWidget(row(staged: false));
    expect(find.text('add'), findsOneWidget);
  });
}
