import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/inbox.dart';
import 'package:nvimos_poc/tasks/parse.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

List<String> task(int n, String status, {List<String> verify = const []}) => [
  '---',
  'id: TASK-$n',
  'title: task $n',
  'status: $status',
  '---',
  if (verify.isNotEmpty) ...['', '## Verify', '', ...verify],
];

void main() {
  test('inbox: changed since last seen, then each attention rule', () {
    final s = Session(port: 1);
    final ws = Workspace(s);
    final seen = DateTime(2026, 11, 1);
    final old = DateTime(2026, 10, 1), recent = DateTime(2026, 11, 9);
    ws.tasks = [
      parseTask('backlog/tasks/task-1 - a.md', task(1, 'Needs Test', verify: ['- [ ] try', '- [x] done']), mtime: recent),
      parseTask('backlog/tasks/task-2 - b.md', task(2, 'In Progress'), mtime: old),
      parseTask('backlog/tasks/task-3 - c.md', task(3, 'To Do'), mtime: old),
      parseTask('backlog/tasks/task-4 - d.md', task(4, 'Done'), mtime: old),
    ];
    ws.changes = parseChanges(
      {
        'openspec/changes/3-c/proposal.md': ['# 3. c', '', 'Status: In Progress (backlog TASK-3)'],
        'openspec/changes/3-c/tasks.md': ['# Tasks', '', '## 1. Build', '', '- [x] 1.1 a', '- [ ] 1.2 b'],
      },
      {'openspec/changes/3-c/tasks.md': old},
    );
    ws.legacy = parseLegacy('todo-2027.md', ['- [x] thing; untested', '- [x] tested thing']);
    ws.branches = Branches({
      'current': 'main',
      'branches': [
        {'name': 'main', 'date': 0},
        {'name': 'agent/task-3', 'date': recent.millisecondsSinceEpoch ~/ 1000, 'subject': 'agent work'},
      ],
    });
    ws.ahead['agent/task-3'] = 2;

    final items = inbox(ws, seen, now: DateTime(2026, 11, 10));
    String key(InboxItem i) => '${i.section}: ${i.task?.id ?? i.change?.id ?? i.legacy?.text ?? i.branch?.name}';
    expect(items.map(key), [
      '$sinceSection: TASK-1',
      '$sinceSection: TASK-3', // the branch's new commits, shown as its task
      'Waiting to be tried: TASK-1',
      'Branches with unreviewed commits: TASK-3',
      'In progress without a change: TASK-2',
      'Stale active changes: 3-c',
      'Legacy notes marked untested: thing; untested',
    ]);
    expect(items[2].why, '1 verify steps left');
    ws.dispose();
    s.dispose();
  });
}
