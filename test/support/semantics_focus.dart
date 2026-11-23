import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The ids of the semantics nodes flagged focused, the node the Windows accessibility bridge takes
/// as the focus. When this id changes while the keyboard stays in one field, the bridge sends the
/// old node "lost accessibility focus", and a Material TextField on Windows unfocuses on that.
List<int> focusedSemanticsIds(WidgetTester t) {
  final root = t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  final ids = <int>[];
  void walk(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isFocused.toString().endsWith('isTrue')) ids.add(node.id);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return ids;
}

/// Types [text] into the focused field, as the platform would, and lets the frames after it run.
Future<void> typeInto(WidgetTester t, String text) async {
  t.testTextInput.updateEditingValue(TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

/// Expects the focused semantics node of the field [focus] to stay the same node while its text
/// goes from empty to [text].
Future<void> expectStableFocusWhileTyping(WidgetTester t, FocusNode focus, {String text = 'h'}) async {
  focus.requestFocus();
  await t.pump();
  final before = focusedSemanticsIds(t);
  expect(before, hasLength(1), reason: 'one focused node, the field');
  await typeInto(t, text);
  expect(
    focusedSemanticsIds(t),
    before,
    reason: 'the first letter must not give the field a new semantics node: on Windows the field '
        'would lose the keyboard',
  );
  expect(focus.hasFocus, isTrue);
}
