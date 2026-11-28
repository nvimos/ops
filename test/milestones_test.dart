import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/tasks/edits.dart';
import 'package:nvimos_poc/tasks/milestones.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/parse.dart';

MilestoneInput c(String key, {DateTime? archived, String planned = ''}) =>
    (key: key, archived: archived != null, archiveDate: archived, planned: planned);

Change change(List<String> proposal) =>
    parseChanges({'openspec/changes/x/proposal.md': proposal}, {}).single;

void main() {
  test("a proposal's own milestone comes from its Milestone: line", () {
    expect(change(['# x', '', 'Status: To Do', 'Milestone: v1 launch ', '']).milestone, 'v1 launch');
    expect(change(['# x', '', 'Status: To Do']).milestone, '');
  });

  group('milestone edits', () {
    final task = parseTask('backlog/tasks/task-1 - a.md', ['---', 'id: TASK-1', 'status: To Do', '---', '', 'body']);
    final planned = parseTask('backlog/tasks/task-1 - a.md', ['---', 'id: TASK-1', 'milestone: 2027 Q1', '---']);

    test("a task's milestone: field is added, replaced and removed", () {
      expect(applyEdits(task.lines, taskMilestoneEdits(task, '2027 Q1')),
          ['---', 'id: TASK-1', 'status: To Do', 'milestone: 2027 Q1', '---', '', 'body']);
      expect(applyEdits(planned.lines, taskMilestoneEdits(planned, 'v1 launch')),
          ['---', 'id: TASK-1', 'milestone: v1 launch', '---']);
      expect(applyEdits(planned.lines, taskMilestoneEdits(planned, '')), ['---', 'id: TASK-1', '---']);
      final back = parseTask(task.path, applyEdits(task.lines, taskMilestoneEdits(task, '2027 Q1')));
      expect(back.milestone, '2027 Q1');
    });

    test("with a milestone file, the task also gets milestone_id: next to milestone:", () {
      final added = applyEdits(task.lines, taskMilestoneEdits(task, 'Release 1.0', id: 'm-2'));
      expect(added, ['---', 'id: TASK-1', 'status: To Do', 'milestone: Release 1.0', 'milestone_id: m-2', '---', '', 'body']);
      expect(parseTask(task.path, added).milestoneId, 'm-2');
      // only milestone: there: the id goes right under it
      expect(applyEdits(planned.lines, taskMilestoneEdits(planned, 'Beta', id: 'm-0')),
          ['---', 'id: TASK-1', 'milestone: Beta', 'milestone_id: m-0', '---']);
      // both there: each replaced; a name without a file drops the id; '' drops both
      final both = parseTask(task.path, added);
      expect(applyEdits(both.lines, taskMilestoneEdits(both, 'Beta', id: 'm-0')),
          ['---', 'id: TASK-1', 'status: To Do', 'milestone: Beta', 'milestone_id: m-0', '---', '', 'body']);
      expect(applyEdits(both.lines, taskMilestoneEdits(both, '2027 Q1')),
          ['---', 'id: TASK-1', 'status: To Do', 'milestone: 2027 Q1', '---', '', 'body']);
      expect(applyEdits(both.lines, taskMilestoneEdits(both, '')), ['---', 'id: TASK-1', 'status: To Do', '---', '', 'body']);
    });

    test("a proposal's Milestone: line goes under Status:, else under the title; Milestone-Id: under it", () {
      final p = ['# x', '', 'Status: To Do', '', '## Why'];
      final c = change(p);
      expect(applyEdits(p, changeMilestoneEdits(c, '2027 Q1')), ['# x', '', 'Status: To Do', 'Milestone: 2027 Q1', '', '## Why']);
      expect(applyEdits(p, changeMilestoneEdits(c, 'Beta', id: 'm-0')),
          ['# x', '', 'Status: To Do', 'Milestone: Beta', 'Milestone-Id: m-0', '', '## Why']);
      final noStatus = ['# x', '', '## Why'];
      expect(applyEdits(noStatus, changeMilestoneEdits(change(noStatus), 'v1')), ['# x', 'Milestone: v1', '', '## Why']);
      final has = ['# x', 'Status: To Do', 'Milestone: v1', 'Milestone-Id: m-1'];
      expect(change(has).milestoneId, 'm-1');
      expect(applyEdits(has, changeMilestoneEdits(change(has), 'v2', id: 'm-2')),
          ['# x', 'Status: To Do', 'Milestone: v2', 'Milestone-Id: m-2']);
      expect(applyEdits(has, changeMilestoneEdits(change(has), '')), ['# x', 'Status: To Do']);
      expect(changeMilestoneEdits(c, ''), isEmpty); // nothing to remove
    });
  });

  group('Backlog.md milestone files', () {
    final lines = ['---', 'id: m-3', 'title: "Release \\"1.0\\""', 'due_date: "2026-08-10"', '---', '', '## Description', '', 'The first cut.', ''];

    test('a file parses into its id, title, due date and description; archived is completed', () {
      final m = parseMilestoneFile('backlog/milestones/m-3 - release-"1.0".md', lines)!;
      expect((m.id, m.name, m.date, m.description, m.completed), ('m-3', 'Release "1.0"', DateTime(2026, 8, 10), 'The first cut.', false));
      expect(parseMilestoneFile('backlog/archive/milestones/m-3 - x.md', lines)!.completed, isTrue);
      expect(parseMilestoneFile('backlog/tasks/task-1 - a.md', lines), isNull);
      // no id in the front matter: the one in the file name
      expect(parseMilestoneFile('backlog/milestones/m-7 - y.md', ['---', 'title: y', '---'])!.id, 'm-7');
    });

    test('the file name and the next id follow Backlog.md', () {
      expect(milestoneFilename('m-0', 'Release 1.0'), 'm-0 - release-1.0.md');
      expect(milestoneFilename('m-1', 'a/b: c?'), 'm-1 - ab-c.md');
      expect(milestoneFilename('m-2', 'x' * 60).length, 'm-2 - '.length + 50 + '.md'.length);
      expect(nextMilestoneId([]), 'm-0');
      expect(nextMilestoneId([Milestone('a', null, id: 'm-0'), Milestone('b', null, id: 'm-4', completed: true)]), 'm-5');
    });

    test('a new file is what Backlog.md writes, and reads back', () {
      final (path, out) = newMilestoneFile('m-0', 'Release "1.0"', due: DateTime(2026, 8, 10));
      expect(path, 'backlog/milestones/m-0 - release-1.0.md');
      expect(out, ['---', 'id: m-0', 'title: "Release \\"1.0\\""', 'due_date: "2026-08-10"', '---', '', '## Description', '', 'Milestone: Release "1.0"']);
      final back = parseMilestoneFile(path, out)!;
      expect((back.id, back.name, back.date), ('m-0', 'Release "1.0"', DateTime(2026, 8, 10)));
      expect(newMilestoneFile('m-1', 'Beta').$2, isNot(contains(startsWith('due_date'))));
    });
  });

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
