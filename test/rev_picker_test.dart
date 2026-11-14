import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/file_tree.dart';
import 'package:nvimos_poc/ui/pr_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  testWidgets('the branch drop-down stays closed when the keys land in the picker; typing opens it', (t) async {
    final focus = FocusNode();
    final picked = <String>[];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RevPicker(
                label: 'base',
                value: 'main',
                names: const ['main', 'dev', 'feature/x'],
                focus: focus,
                onPick: picked.add,
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus(); // a key put the keyboard here
    await t.pump();
    expect(find.text('dev'), findsNothing);
    expect(find.text('feature/x'), findsNothing);

    await t.enterText(find.byType(TextField), 'e'); // typing: the list of matches opens
    await t.pump();
    expect(find.text('dev'), findsOneWidget);
    expect(find.text('feature/x'), findsOneWidget);
    expect(find.text('main'), findsNothing); // filtered
    await t.pump(const Duration(seconds: 1)); // let the auto-pick timer run out
    focus.dispose();
  });

  testWidgets('a click on the picker opens the list of all branches, another click closes it', (t) async {
    final focus = FocusNode();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RevPicker(
                label: 'base',
                value: 'main',
                names: const ['main', 'dev', 'feature/x'],
                focus: focus,
                onPick: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(find.text('dev'), findsOneWidget); // every branch is listed
    expect(find.text('feature/x'), findsOneWidget);
    expect(find.text('main'), findsWidgets);

    await t.pump(const Duration(milliseconds: 600)); // not a double click
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(find.text('dev'), findsNothing); // closed again
    focus.dispose();
  });

  testWidgets('entering a file tree from below selects the lowest visible file, not the last one', (t) async {
    final request = ValueNotifier<int>(0);
    final selected = <String>[];
    final files = [for (var i = 1; i <= 30; i++) TreeFile(path: 'f${i.toString().padLeft(2, '0')}.txt', status: 'modified')];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SizedBox(
            height: 130, // room for about four rows
            child: FileTree(files: files, selected: null, onSelect: selected.add, selectBottom: request),
          ),
        ),
      ),
    );
    request.value++;
    await t.pump();
    await t.pump();
    expect(selected, ['f04.txt']); // 4 rows fit in 130 - 8 px of padding
    request.dispose();
  });

  testWidgets('the openList notifier focuses the field and opens the list of all branches', (t) async {
    final focus = FocusNode();
    final open = ValueNotifier<int>(0);
    addTearDown(focus.dispose);
    addTearDown(open.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RevPicker(
                value: 'main',
                names: const ['main', 'dev', 'feature/x'],
                focus: focus,
                onPick: (_) {},
                strict: true,
                openList: open,
              ),
            ),
          ),
        ),
      ),
    );
    expect(focus.hasFocus, isFalse);
    expect(find.text('dev'), findsNothing);

    open.value++;
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(focus.hasFocus, isTrue);
    expect(find.text('dev'), findsOneWidget);
    expect(find.text('feature/x'), findsOneWidget);
  });
}
