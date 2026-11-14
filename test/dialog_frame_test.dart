import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/tasks/dialogs.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  testWidgets('a form modal has selectable text and its fields still type and submit', (t) async {
    NewTask? made;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => made = await showDialog<NewTask>(
              context: context,
              builder: (_) => const NewTaskDialog(statuses: ['To Do', 'Done']),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.descendant(of: find.byType(SelectionArea), matching: find.text('New task')), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'a selectable title');
    await t.pump();
    expect(find.text('a selectable title'), findsOneWidget);
    await t.testTextInput.receiveAction(TextInputAction.done); // Enter in the title creates the task
    await t.pumpAndSettle();
    expect(made?.title, 'a selectable title');
  });
}
