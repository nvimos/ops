import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/tasks/milestones.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/parse.dart';

MilestoneInput c(String key, {DateTime? archived, String planned = ''}) =>
    (key: key, archived: archived != null, archiveDate: archived, planned: planned);

void main() {
  test("a task's milestone comes from its front matter", () {
    final t = parseTask('backlog/tasks/task-1 - a.md', ['---', 'id: TASK-1', "milestone: '2027 Q1'", '---']);
    expect(t.milestone, '2027 Q1');
    expect(parseTask('backlog/tasks/task-2 - b.md', ['---', 'id: TASK-2', '---']).milestone, '');
  });

  test('names imply closing dates', () {
    expect(milestoneDate('2027 Q1'), DateTime(2027, 3, 31));
    expect(milestoneDate('2027-q4'), DateTime(2027, 12, 31));
    expect(milestoneDate('2027-02'), DateTime(2027, 2, 28));
    expect(milestoneDate('2027'), DateTime(2027, 12, 31));
    expect(milestoneDate('v1 launch'), isNull);
  });

  test('planned changes go to their milestone, the rest by archive date or to Next', () {
    final dated = [Milestone('2026-10', DateTime(2026, 10, 31)), Milestone('2026-11', DateTime(2026, 11, 30))];
    final plan = planMilestones(dated, [
      c('open'),
      c('oct', archived: DateTime(2026, 10, 27)),
      c('nov', archived: DateTime(2026, 11, 7)),
      c('late', archived: DateTime(2026, 12, 2)),
      c('q1', planned: '2027 Q1'),
      c('q1-done', archived: DateTime(2026, 11, 11), planned: '2027 Q1'),
      c('launch', planned: 'v1 launch'),
      c('in-nov', planned: '2026-11'),
    ]);
    expect(plan.of, {
      'open': openMilestone,
      'oct': '2026-10',
      'nov': '2026-11',
      'q1': '2027 Q1',
      'q1-done': '2027 Q1',
      'launch': 'v1 launch',
      'in-nov': '2026-11',
    });
    expect(plan.milestones.map((m) => (m.name, m.planned)), [
      ('2026-10', false),
      ('2026-11', false),
      ('2027 Q1', true),
      ('v1 launch', true),
    ]);
    expect(plan.milestones[2].date, DateTime(2027, 3, 31));
  });
}
