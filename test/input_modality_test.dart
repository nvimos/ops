import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/input_modality.dart';
import 'package:nvimos_poc/ui/widgets.dart';

/// A row that says whether it is hovered, so the test can read the rule without a colour.
class ProbeRow extends StatelessWidget {
  const ProbeRow({super.key});

  @override
  Widget build(BuildContext context) => HoverRow(
    child: Builder(
      builder: (context) => Text(RowHover.of(context) ? 'hover' : 'plain'),
    ),
  );
}

void main() {
  tearDown(InputModality.instance.reset);

  test('a key press hides hover, and using the pointer shows it again', () {
    final modality = InputModality.instance;
    expect(modality.isPointer, isTrue, reason: 'the pointer leads until a key goes down');

    var changes = 0;
    void count() => changes++;
    modality.addListener(count);
    addTearDown(() => modality.removeListener(count));

    modality.keyboardUsed();
    expect(modality.isKeyboard, isTrue);
    modality.keyboardUsed();
    expect(changes, 1, reason: 'only a change of device notifies');

    modality.pointerUsed();
    expect(modality.isPointer, isTrue);
    expect(changes, 2);
  });

  testWidgets('the keys suppress the hover of the row under a resting mouse; a move brings it back', (t) async {
    final stop = InputModality.instance.watch();
    addTearDown(stop);
    await t.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 200, child: ProbeRow())))),
    );

    String probe() => t.widget<Text>(find.descendant(of: find.byType(ProbeRow), matching: find.byType(Text))).data!;
    expect(probe(), 'plain', reason: 'nothing is under the mouse yet');

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final center = t.getCenter(find.byType(ProbeRow));
    await mouse.moveTo(center);
    await t.pump();
    expect(probe(), 'hover', reason: 'the mouse moved onto the row');

    // The keyboard takes over: a key press, then the list would scroll under the resting mouse.
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.pump();
    expect(probe(), 'plain', reason: 'a hover look belongs to the pointer');

    await mouse.moveTo(center + const Offset(1, 0));
    await t.pump();
    expect(probe(), 'hover', reason: 'the mouse moved again: hover is the pointer\'s');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
