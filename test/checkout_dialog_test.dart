import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/backend/backend.dart' show CheckoutHow;
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/ui/checkout_dialog.dart';

void main() {
  final files = [
    StatusFile({'path': 'src/a.txt', 'index': ' ', 'worktree': 'M', 'unstaged': true}),
  ];

  Future<List<CheckoutHow?>> open(WidgetTester tester) async {
    final answers = <CheckoutHow?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(await askCheckout(context, branch: 'other', files: files)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    return answers;
  }

  testWidgets('lists the files; Enter and Space press Cancel, never the discard', (tester) async {
    final answers = await open(tester);
    expect(find.text('src/a.txt'), findsOneWidget);
    expect(find.text('Stash and checkout'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 400));
    expect(answers, [null]);

    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 400));
    expect(answers, [null, null]);
  });

  testWidgets('the other buttons answer stash and force', (tester) async {
    final answers = await open(tester);
    await tester.tap(find.text('Stash and checkout'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Checkout and discard'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(answers, [CheckoutHow.stash, CheckoutHow.force]);
  });
}
