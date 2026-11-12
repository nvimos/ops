import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/list_pair.dart';
import 'package:nvimos_poc/ui/file_tree.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  // Many folders, the last one with a single file: the shape that used to scroll too little.
  final paths = [
    'root.txt',
    for (var d = 1; d <= 12; d++)
      for (var f = 1; f <= 3; f++) 'dir$d/file$f.txt',
    'zlast/only.txt',
  ];
  final order = [...paths]..sort(compareTreeOrder);

  for (final scale in [1.0, 1.7]) {
    // Larger text makes every row taller: nothing here may depend on a row height.
    testWidgets('the selected file is always on screen while walking down and up a long tree (text x$scale)', (t) async {
    final selected = ValueNotifier<String?>(order.first);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 320,
              child: ValueListenableBuilder<String?>(
                valueListenable: selected,
                builder: (context, sel, _) => FileTree(
                  key: const ValueKey('tree'),
                  files: [for (final p in paths) TreeFile(path: p, status: 'modified')],
                  selected: sel,
                  onSelect: (p) => selected.value = p,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    final view = t.getRect(find.byKey(const ValueKey('tree')));

    Future<void> check(String path) async {
      selected.value = path;
      await t.pump();
      await t.pump();
      final row = find.byWidgetPredicate((w) => w is FileRow && w.file.path == path);
      expect(row, findsOneWidget, reason: path);
      final r = t.getRect(row);
      expect(r.top, greaterThanOrEqualTo(view.top - 0.5), reason: '$path above the view');
      expect(r.bottom, lessThanOrEqualTo(view.bottom + 0.5), reason: '$path below the view');
    }

    for (final p in order) {
      await check(p); // down, one file at a time, to the last one
    }
    for (final p in order.reversed) {
      await check(p); // and back up
    }
    selected.dispose();
  });
  }

  testWidgets('jumping straight to the last file shows it', (t) async {
    final selected = ValueNotifier<String?>(order.first);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 320,
              child: ValueListenableBuilder<String?>(
                valueListenable: selected,
                builder: (context, sel, _) => FileTree(
                  key: const ValueKey('tree'),
                  files: [for (final p in paths) TreeFile(path: p, status: 'modified')],
                  selected: sel,
                  onSelect: (p) => selected.value = p,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    selected.value = order.last; // G: far beyond what is built
    await t.pump();
    await t.pump();
    final row = find.byWidgetPredicate((w) => w is FileRow && w.file.path == order.last);
    expect(row, findsOneWidget);
    expect(t.getRect(row).bottom, lessThanOrEqualTo(t.getRect(find.byKey(const ValueKey('tree'))).bottom + 0.5));
    selected.dispose();
  });
}
