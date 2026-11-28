import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/picker_focus.dart';
import 'package:nvimos_poc/ui/file_tree.dart';
import 'package:nvimos_poc/ui/pr_view.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'package:nvimos_poc/ui/widgets.dart';
import 'support/tooltip_semantics.dart';

void main() {
  testWidgets('the branch drop-down stays closed when the keys land in the picker; typing opens it', (t) async {
    final focus = PickerFocusNode();
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
    await expectTooltipsInSemantics(t);
  });

  testWidgets('a click on the picker opens the list of all branches, another click closes it', (t) async {
    final focus = PickerFocusNode();
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

  testWidgets('with the list open, Down moves the highlight and Space picks the highlighted branch', (t) async {
    final focus = PickerFocusNode();
    final picked = <String>[];
    addTearDown(focus.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RevPicker(value: 'main', names: const ['main', 'dev', 'feature/x'], focus: focus, onPick: picked.add),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(TextField)); // opens the list of all branches
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // main -> dev
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // dev -> feature/x
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // stays on the last one
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(picked, ['feature/x']);
    expect(find.text('dev'), findsNothing); // the list closed with the pick
  });

  testWidgets('a branch already merged into base is struck through in the list, and says so', (t) async {
    final focus = PickerFocusNode();
    addTearDown(focus.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RevPicker(value: 'dev', names: const ['dev', 'done'], merged: const {'done'}, focus: focus, onPick: (_) {}),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(TextField)); // opens the list of all branches
    await t.pump();
    TextDecoration? deco(String name) =>
        t.widget<Text>(find.descendant(of: find.byType(ListView), matching: find.text(name))).style?.decoration;
    expect(deco('done'), TextDecoration.lineThrough);
    expect(deco('dev'), isNot(TextDecoration.lineThrough));
    expect(find.byTooltip('done: already merged into base'), findsOneWidget);
    await expectTooltipsInSemantics(t);
  });

  testWidgets('Down past the visible rows moves the highlight on; Space picks it', (t) async {
    final focus = PickerFocusNode();
    final picked = <String>[];
    addTearDown(focus.dispose);
    final names = [for (var i = 0; i < 60; i++) 'b${i.toString().padLeft(2, '0')}'];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RevPicker(value: 'b00', names: names, focus: focus, onPick: picked.add),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(TextField));
    await t.pump();
    for (var i = 0; i < 41; i++) { // the first Down takes the focus into the list, the rest step it
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
    }
    await t.pump();
    final row = find.descendant(of: find.byType(HoverRow), matching: find.text('b40'));
    expect(row.hitTestable(), findsOneWidget); // scrolled into view
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(picked, ['b40']);
  });

  testWidgets('Up from the first item returns to the field; Escape closes the list; Down reopens it', (t) async {
    final focus = PickerFocusNode();
    addTearDown(focus.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RevPicker(value: 'main', names: const ['main', 'dev', 'feature/x'], focus: focus, onPick: (_) {}),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(TextField));
    await t.pump();
    String field() => t.widget<TextField>(find.byType(TextField)).controller!.text;
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // into the list: the first item
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // the second
    await t.pump();
    expect(field(), 'dev'); // the field shows the item the keyboard is on
    expect(find.text('feature/x'), findsOneWidget); // the list still has every branch
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // the first
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // past the first: back to the field
    await t.pump();
    expect(field(), 'main'); // with its text back
    expect(find.text('dev'), findsOneWidget); // the list is still open
    expect(focus.hasPrimaryFocus, isTrue); // the keyboard stays in the field

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.text('dev'), findsNothing); // Escape closes it, the focus stays in the field
    expect(focus.hasPrimaryFocus, isTrue);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // opens it again
    await t.pump();
    expect(find.text('dev'), findsOneWidget);
  });

  testWidgets('Down in an empty field opens the list and highlights the top item', (t) async {
    final focus = PickerFocusNode();
    final picked = <String>[];
    addTearDown(focus.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RevPicker(value: '', names: const ['main', 'dev', 'feature/x'], focus: focus, onPick: picked.add),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape); // close the list the tap opened
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // opens it and highlights the top item
    await t.pump();
    final selected = t.widgetList<HoverRow>(find.byType(HoverRow)).where((w) => w.selected).toList();
    expect(selected, hasLength(1));
    expect(selected.single.selectedColor, isNot(C.surface2)); // visible on the drop-down's box
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'main'); // shown in the field
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(picked, ['main']);
  });

  testWidgets('the openList notifier focuses the field and opens the list of all branches', (t) async {
    final focus = PickerFocusNode();
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
