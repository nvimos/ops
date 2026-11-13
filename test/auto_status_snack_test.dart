import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/error_view.dart';

void main() {
  late Widget app;
  var undone = 0;

  setUp(() {
    undone = 0;
    app = MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAutoStatus(context, 'TASK-1 is Done now', onUndo: () => undone++),
            child: const Text('go'),
          ),
        ),
      ),
    );
  });

  Future<void> show(WidgetTester t) async {
    await t.pumpWidget(app);
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300)); // slides in
  }

  testWidgets('goes away after 3 seconds', (t) async {
    await show(t);
    expect(find.text('TASK-1 is Done now'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 2500));
    expect(find.text('TASK-1 is Done now'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    expect(find.text('TASK-1 is Done now'), findsNothing);
  });

  testWidgets('stays while the mouse is over it, and goes when the mouse leaves', (t) async {
    await show(t);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.text('TASK-1 is Done now')));
    await t.pump();

    await t.pump(const Duration(seconds: 10));
    expect(find.text('TASK-1 is Done now'), findsOneWidget);

    await mouse.moveTo(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.text('TASK-1 is Done now'), findsNothing);
  });

  testWidgets('Undo undoes and closes the note', (t) async {
    await show(t);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('TASK-1 is Done now'), findsNothing);
  });
}
