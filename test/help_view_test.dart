import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/ui/help_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  searchTests();
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

  testWidgets('Down in the search goes into the grid on its first key, whatever the field holds; arrows then move between keys', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));
    final search = find.byType(TextField);
    await tester.tap(search);
    await tester.enterText(search, 'gg');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final first = FocusManager.instance.primaryFocus?.debugLabel;
    expect(first, 'help key ${keyTable.first.$2.first.$1}');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot(first));
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('help key'));
  });

  testWidgets('the key table lays out without overflowing; a narrow pane scrolls', (tester) async {
    tester.view.physicalSize = const Size(1600, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));
    expect(tester.takeException(), isNull, reason: 'no row or column overflows');
    for (final (title, _) in keyTable) {
      expect(find.text(title.toUpperCase()), findsOneWidget, reason: title);
    }
    // Every group is in the scroll view, so a screen too short for all of them still reaches them.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  RichText description(WidgetTester tester) => tester.widget<RichText>(
    find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('previous or next mode'),
    ),
  );

  testWidgets('a single width change reflows at once and never freezes', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));

    tester.view.physicalSize = const Size(1250, 900);
    await tester.pump();
    expect(description(tester).maxLines, isNull, reason: 'a one-off jump reflows directly');
    expect(find.ancestor(of: find.byType(SelectionArea), matching: find.byType(Transform)), findsNothing);
    for (var t = 0; t < 4; t++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(description(tester).maxLines, isNull, reason: 'still wrapping after ${(t + 1) * 50} ms');
    }
  });

  testWidgets('a drag freezes the table: one compact rebuild, then only layout', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));

    tester.view.physicalSize = const Size(1250, 900);
    await tester.pump();
    expect(description(tester).maxLines, isNull, reason: 'the first change reflows at once');

    tester.view.physicalSize = const Size(1275, 900);
    await tester.pump(const Duration(milliseconds: 50));
    expect(description(tester).maxLines, 1, reason: 'a second change within 150 ms freezes');

    final before = tester.widgetList<RichText>(find.byType(RichText)).toList();
    tester.view.physicalSize = const Size(1300, 900);
    await tester.pump();
    final after = tester.widgetList<RichText>(find.byType(RichText)).toList();
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(identical(before[i], after[i]), isTrue, reason: 'a drag frame rebuilt rich text $i');
    }

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(); // the timer's setState builds on the next frame
    expect(description(tester).maxLines, isNull, reason: 'the table reflowed with wrapping at rest');
  });

  testWidgets('a column stops at 250 px and the right edge clips', (tester) async {
    tester.view.physicalSize = const Size(200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));
    // The column keeps 250 px; its 24 px right gap lives inside it, so the table is 226 px.
    expect(tester.getSize(find.byType(Table).first).width, greaterThanOrEqualTo(226));
  });

  testWidgets('the key table text is selectable', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SelectionArea), matching: find.text(keyTable.last.$2.last.$2)),
      findsOneWidget,
    );
  });

  test('key labels have no slash between keys; arrows are icons', () {
    for (final (group, rows) in keyTable) {
      for (final (keys, _) in rows) {
        if (keys == '/') continue; // the filter key itself
        expect(keys, isNot(contains(' / ')), reason: '$group: $keys');
      }
    }
    final spans = KeyLabel.spans('Shift+{up}{down}, JK');
    expect(spans.whereType<WidgetSpan>().length, 2); // the arrows; Shift is coloured text
    expect(TextSpan(children: spans).toPlainText(includePlaceholders: false), 'Shift+, JK');
    final plus = spans.whereType<TextSpan>().firstWhere((t) => t.text == '+');
    expect(plus.style!.color, C.border); // the plus fades into the background
    final comma = spans.whereType<TextSpan>().firstWhere((t) => t.text == ',');
    expect(comma.style!.color, C.border); // and so does the comma between alternatives
  });

  testWidgets('arrow keys show as icons in the table', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HelpView())));
    expect(find.byIcon(Icons.keyboard_arrow_up), findsWidgets);
    expect(find.byIcon(Icons.keyboard_arrow_right), findsWidgets);
    expect(find.textContaining('Up'), findsNothing);
  });

  test('bracket keys list the left bracket first', () {
    final keys = [for (final (_, rows) in keyTable) for (final (k, _) in rows) k];
    expect(keys, containsAll(['Alt+[]', '[f  ]f', '[c  ]c']));
    expect(keys.where((k) => k.contains(']') && (!k.contains('[') || k.indexOf(']') < k.indexOf('['))), isEmpty);
  });

  testWidgets('every key is accent-coloured; plus and comma fade; no box around a key', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KeyLabel('Ctrl+Enter, jk'))));
    final root = tester.widget<RichText>(find.descendant(of: find.byType(KeyLabel), matching: find.byType(RichText))).text as TextSpan;
    expect((root.children!.first as TextSpan).style!.color, C.accent); // letters and named keys alike
    final spans = KeyLabel.spans('Ctrl+Enter, jk').whereType<TextSpan>().toList();
    Color? colour(String t) => spans.firstWhere((s) => s.toPlainText() == t).style?.color;
    expect(colour('Ctrl'), C.accent);
    expect(colour('+'), C.border);
    expect(colour(','), C.border);
    expect(colour(' jk'), isNull); // inherits the accent colour
    expect(KeyLabel.spans('Ctrl+Enter').whereType<WidgetSpan>(), isEmpty);
  });

  test('descriptions use words (or, and), not slashes between alternatives', () {
    for (final (group, rows) in keyTable) {
      for (final (keys, what) in rows) {
        expect(what, isNot(contains(' / ')), reason: '$group: $keys');
      }
    }
  });
}

// Help search ----------------------------------------------------------------------------------

/// How many spans of the table are highlighted.
int highlighted(WidgetTester tester) {
  var n = 0;
  void visit(InlineSpan s) {
    if (s is TextSpan) {
      if (s.style?.backgroundColor == C.found) n++;
      s.children?.forEach(visit);
    }
  }

  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(r.text);
  }
  return n;
}

void searchTests() {
  testWidgets('typing in Help highlights the matches; / clears the input and the highlights', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<HelpViewState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HelpView(key: key))));
    expect(highlighted(tester), 0);

    key.currentState!.type('s'); // a key typed anywhere starts the search
    key.currentState!.type('t');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'st');
    final some = highlighted(tester);
    expect(some, greaterThan(0));

    await tester.enterText(find.byType(TextField), 'stage');
    await tester.pump();
    expect(highlighted(tester), greaterThan(0));
    expect(highlighted(tester), lessThan(some)); // a longer text matches less

    key.currentState!.startSearch(); // `/`
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(highlighted(tester), 0);
  });

  test('highlight marks every case-insensitive match and nothing for an empty query', () {
    String marked(String text, String q) => [
      for (final s in highlight(text, q).cast<TextSpan>()) if (s.style?.backgroundColor == C.found) s.text,
    ].join('|');
    expect(marked('Stage or unstage', 'STAGE'), 'Stage|stage');
    expect(marked('Stage', ''), '');
    expect(marked('abc', 'x'), '');
  });
}
