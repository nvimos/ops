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
    expect(keys.where((k) => k.contains(']') && k.indexOf(']') < (k.indexOf('[') < 0 ? 1 << 20 : k.indexOf('['))), isEmpty);
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
