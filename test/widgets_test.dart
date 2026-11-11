import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/diff_view.dart';
import 'package:nvimos_poc/ui/error_view.dart';
import 'package:nvimos_poc/ui/shell.dart';
import 'package:nvimos_poc/ui/theme.dart';


DiffFile file() => DiffFile({
  'path': 'a.txt',
  'old_path': 'a.txt',
  'status': 'modified',
  'additions': 2,
  'deletions': 1,
  'hunks': [
    {
      'old_start': 1,
      'old_count': 3,
      'new_start': 1,
      'new_count': 4,
      'lines': [
        {'kind': 'context', 'text': 'keep', 'old': 1, 'new': 1},
        {'kind': 'del', 'text': 'old two', 'old': 2},
        {'kind': 'add', 'text': 'new two', 'new': 2},
        {'kind': 'add', 'text': 'added ${'x' * 300}', 'new': 3},
        {'kind': 'context', 'text': 'end', 'old': 3, 'new': 4},
      ],
    },
  ],
});

Widget app(Widget child) => MaterialApp(theme: buildTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('side-by-side pairs a deletion with the addition after it; extra additions get a blank left side', (t) async {
    final clicks = <(int, bool)>[];
    await t.pumpWidget(app(DiffView(file: file(), sideBySide: true, onLine: (l, old) => clicks.add((l, old)))));
    expect(find.text('keep'), findsNWidgets(2)); // context on both sides
    expect(find.text('old two'), findsOneWidget);
    expect(find.text('new two'), findsOneWidget);
    final oldTwo = t.getTopLeft(find.text('old two'));
    final newTwo = t.getTopLeft(find.text('new two'));
    expect(oldTwo.dy, newTwo.dy); // same row
    expect(oldTwo.dx, lessThan(newTwo.dx));
    await t.tap(find.text('old two'));
    await t.tap(find.text('new two'));
    expect(clicks, [(2, true), (2, false)]);
  });

  testWidgets('unwrapped unified lines stay on one line and scroll sideways', (t) async {
    await t.pumpWidget(app(DiffView(file: file(), wrap: false)));
    expect(find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal), findsOneWidget);
    final h = t.getSize(find.textContaining('added xxx')).height;
    expect(h, lessThan(30));
  });

  testWidgets('an error pane shows the short message and the full trace, selectable', (t) async {
    const err = 'NvimError(nvim_exec_lua): Lua: nvimos: git diff: bad revision\nstack traceback:\n  [C]: in function error';
    await t.pumpWidget(app(const ErrorPane(err)));
    expect(find.text('git diff: bad revision'), findsOneWidget);
    expect(find.text(err), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(shortError(err), 'git diff: bad revision');
  });

  testWidgets('the sidebar expands with labels and lists the Directories mode', (t) async {
    // Never connected: widget tests run on a fake clock, so no sockets here.
    final s = Session(port: 1);
    await t.pumpWidget(SessionScope(session: s, child: MaterialApp(theme: buildTheme(), home: const Shell())));
    expect(find.text('Directories'), findsNothing); // collapsed: icons only
    await t.tap(find.byIcon(Icons.chevron_right));
    await t.pump(const Duration(milliseconds: 300)); // the rail's width animation
    for (final m in ['Pull request', 'Changes', 'Tasks', 'Directories']) {
      expect(find.text(m), findsOneWidget);
    }
    s.dispose();
  });
}
