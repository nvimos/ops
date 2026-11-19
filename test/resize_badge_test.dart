import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/resize_badge.dart';

void main() {
  testWidgets('the badge shows width X height while the edge is held', (tester) async {
    final dragging = ValueNotifier(false);
    addTearDown(dragging.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: Stack(children: [Positioned.fill(child: ResizeBadge(width: 400, height: 300, dragging: dragging))]),
            ),
          ),
        ),
      ),
    );
    expect(find.text('400 X 300'), findsNothing);

    dragging.value = true;
    await tester.pump();
    expect(find.text('400 X 300'), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets); // it never takes the pointer from the drag

    dragging.value = false;
    await tester.pump();
    expect(find.text('400 X 300'), findsNothing);
  });

  testWidgets('the badge follows the pane size it is given', (tester) async {
    final dragging = ValueNotifier(true);
    addTearDown(dragging.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResizeBadge(width: 1234, height: 567, dragging: dragging),
        ),
      ),
    );
    expect(find.text('1234 X 567'), findsOneWidget);
  });
}
