import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/browser.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/parse.dart';
import 'package:nvimos_poc/tasks/sorter.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/ui/tasks/tasks_nav.dart';

/// Dummy tasks whose orders differ in every mode and have no ties.
///
///   task   title        length  created     modified
///   TASK-1 Mango        5       2026-01-03  Jan 3
///   TASK-2 apple pie    9       2026-01-01  Jan 5
///   TASK-3 Zed          3       2026-01-02  Jan 1
///   TASK-4 kiwi         4       2026-01-04  Jan 4
Task task(int n, String title, String created, int day) => parseTask(
  'backlog/tasks/task-$n - t.md',
  ['---', 'id: TASK-$n', 'title: $title', "created_date: '$created'", 'status: To Do', '---'],
  mtime: DateTime(2026, 1, day),
);

final tasks = [
  task(1, 'Mango', '2026-01-03', 3),
  task(2, 'apple pie', '2026-01-01', 5),
  task(3, 'Zed', '2026-01-02', 1),
  task(4, 'kiwi', '2026-01-04', 4),
];

/// Dummy changes: the id, a proposal with the title, and the proposal's modification time.
///
///   change  title        length  modified
///   1-b     Zulu         4       Jan 7
///   2-a     alpha beta   10      Jan 2
///   3-c     Mid          3       Jan 5
List<Change> changes() {
  Map<String, List<String>> proposal(String dir, String title) => {'openspec/changes/$dir/proposal.md': ['# $title']};
  return parseChanges(
    {...proposal('1-b', 'Zulu'), ...proposal('2-a', 'alpha beta'), ...proposal('3-c', 'Mid')},
    {
      'openspec/changes/1-b/proposal.md': DateTime(2026, 1, 7),
      'openspec/changes/2-a/proposal.md': DateTime(2026, 1, 2),
      'openspec/changes/3-c/proposal.md': DateTime(2026, 1, 5),
    },
  )..sort((a, b) => a.id.compareTo(b.id));
}

/// Cycles [s] to the mode with the one-word [word] and sets the direction.
void use(Sorter<dynamic> s, String word, {required bool descending}) {
  for (var i = 0; i < s.modes.length && s.mode.word != word; i++) {
    s.cycle();
  }
  expect(s.mode.word, word);
  if (s.descending != descending) s.reverse();
}

void main() {
  group('task list', () {
    late Session session;
    late Workspace ws;
    late TaskBrowser browser;

    setUp(() {
      session = Session();
      ws = Workspace(session)..tasks = tasks;
      browser = TaskBrowser(ws, lastSeen: () => DateTime(2000));
    });

    tearDown(() {
      browser.dispose();
      ws.dispose();
      session.dispose();
    });

    List<int> order() => [for (final t in browser.visibleTasks) t.number];

    // mode: [ascending order, as task numbers]; descending is the same list backwards
    const expected = {
      'name': [2, 4, 1, 3], // apple pie, kiwi, Mango, Zed (case ignored)
      'modified': [3, 1, 4, 2],
      'created': [2, 3, 1, 4],
      'length': [3, 4, 1, 2],
    };

    for (final e in expected.entries) {
      test('${e.key}, ascending', () {
        use(browser.taskSort, e.key, descending: false);
        expect(order(), e.value);
      });
      test('${e.key}, descending', () {
        use(browser.taskSort, e.key, descending: true);
        expect(order(), e.value.reversed.toList());
      });
    }

    test('the modes cycle name, modified, created, length and round again', () {
      use(browser.taskSort, 'name', descending: false);
      final seen = <String>[];
      for (var i = 0; i < 5; i++) {
        seen.add(browser.taskSort.mode.word);
        browser.taskSort.cycle();
      }
      expect(seen, ['name', 'modified', 'created', 'length', 'name']);
    });

    test('starts on modified, newest first', () {
      expect(browser.taskSort.mode.word, 'modified');
      expect(browser.taskSort.descending, isTrue);
      expect(order(), [2, 4, 1, 3]);
    });

    test('equal keys keep the incoming order, ascending and descending', () {
      ws.tasks = [task(1, 'aaaa', '2026-01-01', 1), task(2, 'bbbb', '2026-01-01', 1), task(3, 'cc', '2026-01-01', 1)];
      use(browser.taskSort, 'length', descending: false);
      expect(order(), [3, 1, 2]);
      use(browser.taskSort, 'length', descending: true);
      expect(order(), [1, 2, 3]);
    });

    test('the order holds inside each group, and a click notifies', () {
      ws.tasks = [
        ...tasks,
        parseTask('backlog/tasks/task-5 - t.md', [
          '---',
          'id: TASK-5',
          'title: Aa',
          "created_date: '2026-01-05'",
          'status: Done',
          '---',
        ], mtime: DateTime(2026, 1, 9)),
      ];
      use(browser.taskSort, 'name', descending: false);
      browser.view = TView.tasks;
      browser.statusFilter = null;
      var notified = 0;
      browser.addListener(() => notified++);
      browser.taskSort.reverse();
      expect(notified, 1);
      final keys = [for (final r in browser.rows()) if (!r.isHeader) r.key];
      expect(keys, ['TASK-3', 'TASK-1', 'TASK-4', 'TASK-2', 'TASK-5']); // To Do by name, descending; then Done
    });
  });

  group('changes list', () {
    const expected = {
      'id': ['1-b', '2-a', '3-c'],
      'name': ['2-a', '3-c', '1-b'], // alpha beta, Mid, Zulu
      'modified': ['2-a', '3-c', '1-b'],
      'length': ['3-c', '1-b', '2-a'],
    };

    for (final e in expected.entries) {
      for (final descending in [false, true]) {
        test('${e.key}, ${descending ? 'descending' : 'ascending'}', () {
          final s = Sorter<Change>([
            SortMode('By id', 'id', Icons.tag, (a, b) => a.id.compareTo(b.id)),
            SortMode('By name', 'name', Icons.sort_by_alpha, (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
            SortMode('By modification time', 'modified', Icons.update, (a, b) => a.mtime.compareTo(b.mtime)),
            SortMode('By length of the title', 'length', Icons.straighten, (a, b) => a.title.length.compareTo(b.title.length)),
          ]);
          use(s, e.key, descending: descending);
          final ids = [for (final c in s.sorted(changes())) c.id];
          expect(ids, descending ? e.value.reversed.toList() : e.value);
          s.dispose();
        });
      }
    }

    test('the browser sorts the changes the same way, newest modification first at the start', () {
      final session = Session();
      final ws = Workspace(session);
      final browser = TaskBrowser(ws, lastSeen: () => DateTime(2000));
      expect(browser.changeSort.mode.word, 'modified');
      expect(browser.changeSort.descending, isTrue);
      expect([for (final c in browser.changeSort.sorted(changes())) c.id], ['1-b', '3-c', '2-a']);
      browser.dispose();
      ws.dispose();
      session.dispose();
    });
  });

  group('SortButtons', () {
    late Sorter<Task> sorter;

    setUp(() {
      sorter = Sorter<Task>([
        SortMode('By name', 'name', Icons.sort_by_alpha, (a, b) => a.title.compareTo(b.title)),
        SortMode('By modification time', 'modified', Icons.update, (a, b) => a.mtime.compareTo(b.mtime)),
      ], descending: true);
    });

    tearDown(() => sorter.dispose());

    Future<void> pump(WidgetTester t) =>
        t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SortButtons(sorter: sorter)))));

    testWidgets('direction first, then the mode icon, then its word; clicks cycle and reverse', (t) async {
      await pump(t);
      expect(find.text('name'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget); // descending
      final arrow = t.getTopLeft(find.byIcon(Icons.arrow_downward)).dx;
      final mode = t.getTopLeft(find.byIcon(Icons.sort_by_alpha)).dx;
      final word = t.getTopLeft(find.text('name')).dx;
      expect(arrow, lessThan(mode));
      expect(mode, lessThan(word));

      await t.tap(find.byIcon(Icons.sort_by_alpha));
      await t.pump();
      expect(find.text('modified'), findsOneWidget);
      expect(find.byIcon(Icons.update), findsOneWidget);

      await t.tap(find.byIcon(Icons.arrow_downward));
      await t.pump();
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(sorter.descending, isFalse);
    });

    testWidgets('the button keeps one width whichever word it shows', (t) async {
      sorter = Sorter<Task>([
        SortMode('By id', 'id', Icons.tag, (a, b) => 0),
        SortMode('By modification time', 'modified', Icons.update, (a, b) => 0),
      ]);
      await pump(t);
      final widths = <double>[];
      final lefts = <double>[];
      for (var i = 0; i < 2; i++) {
        widths.add(t.getSize(find.byType(SortButtons)).width);
        lefts.add(t.getTopLeft(find.byIcon(Icons.arrow_upward)).dx);
        sorter.cycle();
        await t.pump();
      }
      expect(widths[0], widths[1]);
      expect(lefts[0], lefts[1]);
    });

    testWidgets('a click on the word cycles the mode like a click on the icon', (t) async {
      await pump(t);
      await t.tap(find.text('name'));
      await t.pump();
      expect(find.text('modified'), findsOneWidget);
    });

    testWidgets('the pointer cursor shows over the icon and over the word', (t) async {
      await pump(t);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final f in [find.byIcon(Icons.sort_by_alpha), find.text('name'), find.byIcon(Icons.arrow_downward)]) {
        await mouse.moveTo(t.getCenter(f));
        await t.pump();
        expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
      }
    });

    testWidgets('the tooltips say the mode and the direction', (t) async {
      await pump(t);
      expect(find.byTooltip('By name'), findsOneWidget);
      expect(find.byTooltip('Descending, click to reverse'), findsOneWidget);
      await t.tap(find.byIcon(Icons.arrow_downward));
      await t.pump();
      expect(find.byTooltip('Ascending, click to reverse'), findsOneWidget);
    });
  });

  group('list header', () {
    Future<void> header(WidgetTester t, double width) async {
      final sorter = Sorter<Task>([SortMode('By name', 'name', Icons.sort_by_alpha, (a, b) => 0)]);
      addTearDown(sorter.dispose);
      final filter = TextEditingController();
      final focus = FocusNode();
      addTearDown(filter.dispose);
      addTearDown(focus.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: TaskListHeader(
                  title: 'Needs Test',
                  count: 3,
                  filter: filter,
                  filterFocus: focus,
                  onQuery: (_) {},
                  action: SortButtons(sorter: sorter),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the filter and the buttons sit against the right edge, with a margin', (t) async {
      await header(t, 700);
      final right = t.getTopRight(find.byType(SortButtons)).dx;
      expect(right, closeTo(700 - 14, 1));
      expect(t.getTopLeft(find.text('Needs Test')).dx, closeTo(14, 1));
      expect(t.getTopRight(find.byType(FilterField)).dx, lessThan(t.getTopLeft(find.byType(SortButtons)).dx));
    });

    testWidgets('a narrow header still fits', (t) async {
      await header(t, 420);
      expect(t.takeException(), isNull);
      expect(t.getTopRight(find.byType(SortButtons)).dx, closeTo(420 - 14, 1));
    });
  });
}
