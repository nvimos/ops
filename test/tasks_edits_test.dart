import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/tasks/edits.dart';
import 'package:nvimos_poc/tasks/markdown.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/parse.dart';

final taskLines = [
  '---',
  'id: TASK-7',
  "title: 'a: b'",
  'status: To Do',
  'labels: []',
  '---',
  '',
  '## Verify',
  '',
  '- [ ] try it',
  '  - [x] nested',
];

void main() {
  Task task() => parseTask('backlog/tasks/task-7 - a.md', taskLines);

  test('status edit replaces the status line and expects the old one', () {
    final e = taskStatusEdit(task(), 'Needs Test');
    expect(
      [e.first, e.last, e.lines, e.expect],
      [
        3,
        4,
        ['status: Needs Test'],
        ['status: To Do'],
      ],
    );
    expect(parseTask('x', applyEdits(taskLines, [e])).status, 'Needs Test');
  });

  test('priority edit inserts before ---, replaces, and removes', () {
    final added = applyEdits(taskLines, [taskPriorityEdit(task(), 'high')]);
    expect(added[5], 'priority: high');
    final t2 = parseTask('x', added);
    expect(t2.priority, 'high');
    expect(parseTask('x', applyEdits(added, [taskPriorityEdit(t2, 'low')])).priority, 'low');
    final removed = applyEdits(added, [taskPriorityEdit(t2, '')]);
    expect(removed, taskLines);
  });

  test('checkbox toggles keep indentation and text', () {
    final t = task();
    final c = t.verify.first;
    final lines = applyEdits(taskLines, [toggleCheckEdit(taskLines, c)]);
    expect(lines[9], '- [x] try it');
    final nested = checksIn(taskLines, t.section('Verify')).last;
    expect(applyEdits(taskLines, [toggleCheckEdit(taskLines, nested)])[10], '  - [ ] nested');
  });

  test('change status edit keeps the backlog reference', () {
    final c = parseChanges({
      'openspec/changes/7-a/proposal.md': ['# 7. a', '', 'Status: To Do (backlog TASK-7)'],
    }, {}).single;
    expect(changeStatusEdit(c, 'In Progress')!.lines, ['Status: In Progress (backlog TASK-7)']);
  });

  test('index.tsv row gets the new status', () {
    final index = ['task\tstatus\tchange\ttitle\tfile', 'TASK-7\tTo Do\t7-a\ta\tx.md'];
    expect(indexStatusEdit(index, 'TASK-7', 'Done')!.lines, ['TASK-7\tDone\t7-a\ta\tx.md']);
    expect(indexStatusEdit(index, 'TASK-9', 'Done'), isNull);
  });

  test('a new task file parses back to what was asked', () {
    final (path, lines) = newTaskFile(
      number: 12,
      title: 'oil: preview wraps',
      labels: ['legacy', 'todo-2027'],
      originalNotes: ['- [ ] oil: preview wraps'],
    );
    expect(path, 'backlog/tasks/task-12 - oil-preview-wraps.md');
    final t = parseTask(path, lines);
    expect(
      [t.id, t.title, t.status, t.labels, t.originalNotes],
      [
        'TASK-12',
        'oil: preview wraps',
        'To Do',
        ['legacy', 'todo-2027'],
        ['- [ ] oil: preview wraps'],
      ],
    );
    expect(defaultStatuses, contains(t.status));
  });
}
