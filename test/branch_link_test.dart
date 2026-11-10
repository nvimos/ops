import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/parse.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

void main() {
  test('a branch linked by hand wins over the name rules; unlinking falls back', () async {
    final s = Session(port: 1);
    final ws = Workspace(s);
    final t = parseTask('backlog/tasks/task-5 - x.md', ['---', 'id: TASK-5', 'title: x', 'status: To Do', '---']);
    ws.tasks = [t];
    ws.branches = Branches({
      'current': 'main',
      'branches': [
        {'name': 'main'},
        {'name': 'agent/task-5'},
        {'name': 'claude/oil-preview'},
      ],
    });
    expect(ws.branchFor(t), 'agent/task-5');
    await ws.linkBranch(t, 'claude/oil-preview');
    expect(ws.branchFor(t), 'claude/oil-preview');
    await ws.linkBranch(t, null);
    expect(ws.branchFor(t), 'agent/task-5');
    ws.links['TASK-5'] = 'deleted-branch';
    expect(ws.branchFor(t), 'agent/task-5'); // a link to a branch that's gone is ignored
    ws.dispose();
    s.dispose();
  });
}
