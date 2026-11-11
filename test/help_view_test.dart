import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/ui/help_view.dart';

void main() {
  test('splitColumns keeps the order and evens out the heights', () {
    expect(splitColumns([7, 7, 12, 9, 6, 5], 4), [
      [0, 1],
      [2],
      [3],
      [4, 5],
    ]);
    expect(splitColumns([7, 7, 12, 9, 6, 5], 1), [
      [0, 1, 2, 3, 4, 5],
    ]);
    expect(splitColumns([4, 4], 5), [
      [0],
      [1],
    ]);
  });

  testWidgets('every key group fits on one wide screen', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));
    for (final (title, _) in keyTable) {
      final box = tester.getRect(find.text(title.toUpperCase()));
      expect(box.bottom, lessThan(900), reason: title);
    }
    final last = keyTable.last.$2.last.$2;
    expect(tester.getRect(find.text(last)).bottom, lessThan(900));
  });
}
