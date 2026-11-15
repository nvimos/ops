import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/debug_bar.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  testWidgets('the focus path dialog text can be selected with the mouse', (t) async {
    final focus = FocusNode(debugLabel: 'shell');
    addTearDown(focus.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showFocusPath(context, focus), child: const Text('open')),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final text = find.byType(EditableText);
    final box = t.getRect(text);
    final g = await t.startGesture(box.centerLeft + const Offset(1, 0), kind: PointerDeviceKind.mouse);
    await g.moveBy(Offset(box.width - 2, 0));
    await g.up();
    await t.pump();
    final selection = t.widget<EditableText>(text).controller.selection;
    expect(selection.isCollapsed, isFalse);
    expect(selection.textInside(focus.debugLabel!), 'shell');
  });
}
