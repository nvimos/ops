import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/browser.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/parse.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

void main() {
  test('J/K and a selection keep the rows; a query, the sort and an edit of the workspace build them again', () {
    final s = Session();
    final ws = Workspace(s);
    Task task(int n, String title) => parseTask(
      'backlog/tasks/task-$n - t.md',
      ['---', 'id: TASK-$n', 'title: $title', "created_date: '2026-01-0$n'", 'status: To Do', '---'],
      mtime: DateTime(2026, 1, n),
    );
    ws.tasks = [task(1, 'Alpha'), task(2, 'Bravo'), task(3, 'Charlie')];
    final browser = TaskBrowser(ws, lastSeen: () => DateTime(2000));
    addTearDown(browser.dispose);
    browser.showView(TView.tasks);

    final rows = browser.rows();
    browser.move(1);
    browser.move(1);
    browser.select('TASK-1');
    expect(identical(browser.rows(), rows), isTrue, reason: 'a cursor move or a selection does not rebuild the rows');

    browser.setQuery('bra');
    expect([for (final r in browser.rows()) if (!r.isHeader) r.key], ['TASK-2']);
    browser.setQuery('');
    final all = browser.rows();
    browser.taskSort.reverse();
    expect(identical(browser.rows(), all), isFalse, reason: 'the sort changed');

    final sorted = browser.rows();
    ws.tasks = [...ws.tasks, task(4, 'Delta')];
    expect(browser.rows().where((r) => !r.isHeader), hasLength(4), reason: 'a new task list builds them again');
    expect(identical(browser.rows(), sorted), isFalse);
  });

  test('the sort button cycles the modes; reverse turns the order round', () {
    final s = Session();
    final ws = Workspace(s);
    Task task(int n, String title, String created, int mtime) => parseTask(
      'backlog/tasks/task-$n - t.md',
      ['---', 'id: TASK-$n', 'title: $title', "created_date: '$created'", 'status: To Do', '---'],
      mtime: DateTime(2026, 1, mtime),
    );
    ws.tasks = [
      task(1, 'Bravo', '2026-01-03', 5),
      task(2, 'alpha is long', '2026-01-01', 9),
      task(3, 'Cy', '2026-01-02', 1),
    ];
    final browser = TaskBrowser(ws, lastSeen: () => DateTime(2000));
    List<String> ids() => browser.visibleTasks.map((t) => t.id).toList();

    // The default: newest modification first.
    expect(browser.taskSort.mode.label, 'By modification time');
    expect(browser.taskSort.descending, isTrue);
    expect(ids(), ['TASK-2', 'TASK-1', 'TASK-3']);
    browser.taskSort.reverse();
    expect(ids(), ['TASK-3', 'TASK-1', 'TASK-2']);
    browser.taskSort.reverse();

    browser.taskSort.cycle(); // creation time follows modification time
    expect(browser.taskSort.mode.label, 'By creation time');
    expect(ids(), ['TASK-1', 'TASK-3', 'TASK-2']); // newest first
    browser.taskSort.reverse();
    expect(ids(), ['TASK-2', 'TASK-3', 'TASK-1']);

    browser.taskSort.cycle();
    expect(browser.taskSort.mode.label, 'By length of the title');
    expect(ids(), ['TASK-3', 'TASK-1', 'TASK-2']);
    browser.taskSort.cycle(); // wraps to name
    expect(browser.taskSort.mode.label, 'By name');
    expect(ids(), ['TASK-2', 'TASK-1', 'TASK-3']);

    expect(browser.creationSuspicious, isFalse); // only 3 tasks

    browser.dispose();
    ws.dispose();
    s.dispose();
  });

  test('over 80% of the tasks with one creation time: order by the hint inside the task', () {
    final s = Session();
    final ws = Workspace(s);
    Task task(int n, String labels) => parseTask('backlog/tasks/task-$n - t.md', [
      '---',
      'id: TASK-$n',
      'title: t$n',
      "created_date: '2026-01-01'",
      'labels: [$labels]',
      '---',
    ]);
    ws.tasks = [
      task(1, 'created:2026-03-01'),
      task(2, 'created:2026-02-01'),
      task(3, 'created:2026-01-15'),
      task(4, ''),
      task(5, 'created:2026-04-01'),
    ];
    final browser = TaskBrowser(ws, lastSeen: () => DateTime(2000));
    browser.taskSort.cycle(); // from the default, modification time, to creation time
    expect(browser.taskSort.mode.label, 'By creation time');
    browser.taskSort.reverse(); // oldest first
    expect(browser.creationSuspicious, isTrue);
    expect(browser.visibleTasks.map((t) => t.id), ['TASK-4', 'TASK-3', 'TASK-2', 'TASK-1', 'TASK-5']);
    expect(browser.taskSort.tooltip, contains('Suspicious'));
    browser.taskSort.cycle();
    expect(browser.taskSort.tooltip, isNot(contains('Suspicious')));

    ws.tasks = [...ws.tasks.take(4), parseTask('backlog/tasks/task-9 - t.md', ['---', 'id: TASK-9', "created_date: '2026-02-02'", '---'])];
    expect(browser.creationSuspicious, isFalse); // 4 of 5 is 80%, not more
    browser.dispose();
    ws.dispose();
    s.dispose();
  });
}
