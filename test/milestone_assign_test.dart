import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/milestones.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/ui/tasks/milestone_menu.dart';
import 'package:nvimos_poc/ui/tasks/tasks_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'support/tooltip_semantics.dart';
import 'workspace_test.dart' show planRepo;

/// planRepo plus a change without a task that plans itself, and a stray Milestone: line on the
/// change TASK-1 owns.
Future<Directory> milestoneRepo() async {
  final d = await planRepo();
  await File('${d.path}/openspec/changes/1-first/proposal.md')
      .writeAsString('# 1. first\n\nStatus: To Do (backlog TASK-1)\nMilestone: ignored\n\n## Why\n\nBecause.\n');
  await File('${d.path}/openspec/changes/2-free/proposal.md').create(recursive: true);
  await File('${d.path}/openspec/changes/2-free/proposal.md')
      .writeAsString('# 2. free\n\nStatus: To Do\nMilestone: v1 launch\n\n## Why\n\nBecause.\n');
  await git(d, ['add', '.']);
  await git(d, ['commit', '-q', '-m', 'milestones']);
  return d;
}

/// milestoneRepo plus Backlog.md milestone files: m-0 was "Beta" and is "Beta Renamed" now (TASK-1
/// still says Beta, with its id), m-1 "Alpha" is archived; TASK-2 names alpha without an id; the
/// free proposal names Alpha but its id is m-0.
Future<Directory> milestoneFileRepo() async {
  final d = await milestoneRepo();
  Future<void> w(String p, String s) async {
    await File('${d.path}/$p').create(recursive: true);
    await File('${d.path}/$p').writeAsString(s);
  }

  await w('backlog/milestones/m-0 - beta.md', '---\nid: m-0\ntitle: "Beta Renamed"\ndue_date: "2027-06-30"\n---\n\n## Description\n\nThe beta.\n');
  await w('backlog/archive/milestones/m-1 - alpha.md', '---\nid: m-1\ntitle: "Alpha"\ndue_date: "2026-01-31"\n---\n\n## Description\n\nMilestone: Alpha\n');
  await w(
    'backlog/tasks/task-1 - first.md',
    '---\nid: TASK-1\ntitle: first\nstatus: To Do\nlabels: [a]\nmilestone: Beta\nmilestone_id: m-0\n---\n\n## Verify\n\n- [ ] try it\n',
  );
  await w('backlog/tasks/task-2 - second.md', '---\nid: TASK-2\ntitle: second\nstatus: In Progress\nmilestone: alpha\n---\n');
  await w('openspec/changes/2-free/proposal.md', '# 2. free\n\nStatus: To Do\nMilestone: Alpha\nMilestone-Id: m-0\n\n## Why\n\nBecause.\n');
  await git(d, ['add', '.']);
  await git(d, ['commit', '-q', '-m', 'milestone files']);
  return d;
}

Future<(TestNvim, Session, Workspace, Directory)> open({bool files = false}) async {
  final repo = files ? await milestoneFileRepo() : await milestoneRepo();
  final nvim = await TestNvim.start(cwd: repo);
  await nvim.connect().then((r) => r.close());
  final s = Session(port: nvim.port);
  await s.connect();
  final ws = Workspace(s);
  await until(() => ws.loaded && !ws.loading);
  return (nvim, s, ws, repo);
}

String read(Directory repo, String path) => File('${repo.path}/$path').readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('a change with a task follows the task, one without its own line; edits go to the owner', () async {
    final (nvim, s, ws, repo) = await open();
    addTearDown(() {
      ws.dispose();
      s.dispose();
    });
    Change ch(String id) => ws.changes.firstWhere((c) => c.id == id);

    expect(ws.plannedMilestone(ch('1-first')), ''); // TASK-1 plans nothing; its proposal's line is ignored
    expect(ws.plannedMilestone(ch('2-free')), 'v1 launch');
    expect(ws.changesOf('v1 launch').map((c) => c.id), ['2-free']);
    expect(ws.milestones.firstWhere((m) => m.name == 'v1 launch').planned, isTrue);
    expect(ws.changesOf(openMilestone).map((c) => c.id), ['1-first']);

    // Through the task: TASK-1's file changes, the proposal does not; the view follows at once.
    expect(await ws.setChangeMilestone(ch('1-first'), '2027 Q1'), isNull);
    expect(ws.changesOf('2027 Q1').map((c) => c.id), ['1-first']);
    await until(() => read(repo, 'backlog/tasks/task-1 - first.md').contains('milestone: 2027 Q1'));
    expect(read(repo, 'openspec/changes/1-first/proposal.md'), contains('Milestone: ignored'));

    // Without a task: the proposal's own line, taken off with ''.
    expect(await ws.setChangeMilestone(ch('2-free'), ''), isNull);
    expect(ws.plannedMilestone(ch('2-free')), '');
    await until(() => !read(repo, 'openspec/changes/2-free/proposal.md').contains('Milestone:'));
    expect(ws.changesOf(openMilestone).map((c) => c.id), ['2-free']);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('milestone files: by id first, the name as fallback; a new one is a Backlog.md file', () async {
    final (nvim, s, ws, repo) = await open(files: true);
    addTearDown(() {
      ws.dispose();
      s.dispose();
    });
    Change ch(String id) => ws.changes.firstWhere((c) => c.id == id);

    // Renamed: TASK-1 says Beta, its id m-0 finds the file, which is Beta Renamed now.
    expect(ws.taskMilestone(ws.task('TASK-1')!), 'Beta Renamed');
    // Only milestone: matched against the titles, ignoring case.
    expect(ws.taskMilestone(ws.task('TASK-2')!), 'Alpha');
    // The two disagree: the id wins.
    expect(ws.plannedMilestone(ch('2-free')), 'Beta Renamed');
    expect(ws.changesOf('Beta Renamed').map((c) => c.id), ['1-first', '2-free']);
    final beta = ws.milestones.firstWhere((m) => m.name == 'Beta Renamed');
    expect((beta.id, beta.date, beta.description, beta.planned), ('m-0', DateTime(2027, 6, 30), 'The beta.', false));
    expect(ws.milestones.firstWhere((m) => m.name == 'Alpha').completed, isTrue);
    expect(ws.milestones.where((m) => m.name == 'Beta'), isEmpty); // the old name is not a milestone of its own

    // Reading rewrote nothing; the next edit of TASK-1 writes the current title.
    expect(read(repo, 'backlog/tasks/task-1 - first.md'), contains('milestone: Beta\n'));
    expect(await ws.setTaskPriority(ws.task('TASK-1')!, 'high'), isNull);
    await until(() => read(repo, 'backlog/tasks/task-1 - first.md').contains('milestone: Beta Renamed\nmilestone_id: m-0'));
    expect(read(repo, 'backlog/tasks/task-1 - first.md'), contains('priority: high'));

    // A new milestone: m-2 (above the archived m-1), in memory at once, then on disk as Backlog.md
    // writes it; planning a task for it writes the name and the id.
    final created = ws.createMilestone('Gamma 2', due: DateTime(2027, 9, 30));
    expect(ws.milestoneFile('', 'gamma 2')?.id, 'm-2');
    expect(await ws.setTaskMilestone(ws.task('TASK-2')!, 'Gamma 2'), isNull);
    expect(await created, isNull);
    expect(read(repo, 'backlog/milestones/m-2 - gamma-2.md'),
        '---\nid: m-2\ntitle: "Gamma 2"\ndue_date: "2027-09-30"\n---\n\n## Description\n\nMilestone: Gamma 2\n');
    await until(() => read(repo, 'backlog/tasks/task-2 - second.md').contains('milestone: Gamma 2\nmilestone_id: m-2'));
    expect(await ws.createMilestone('GAMMA 2'), isNull); // exists already: no second file
    expect(Directory('${repo.path}/backlog/milestones').listSync().length, 2);

    // A name without a file: the id goes.
    expect(await ws.setTaskMilestone(ws.task('TASK-2')!, '2028 Q1'), isNull);
    await until(() => !read(repo, 'backlog/tasks/task-2 - second.md').contains('milestone_id'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets("the task's Milestone menu plans a new milestone; Move to… in the Milestones view", (t) async {
    final (nvim, s, ws, repo) = (await t.runAsync(open))!;
    await t.binding.setSurfaceSize(const Size(1400, 900));
    await t.pumpWidget(
      SessionScope(
        session: s,
        child: MaterialApp(theme: buildTheme(), home: Scaffold(body: TasksView(ws: ws))),
      ),
    );
    await t.pump();
    Future<void> tap(Finder f) async {
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 300));
    }

    await tap(find.textContaining('All tasks', findRichText: true).first);
    await tap(find.text('first'));
    expect(find.byType(MilestoneMenu), findsOneWidget);
    expect(find.text('No milestone'), findsOneWidget);
    await expectTooltipsInSemantics(t);

    // The menu shows the pointer, and New milestone… asks for a name.
    final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: t.getCenter(find.text('No milestone')));
    await t.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    await gesture.removePointer();
    await tap(find.text('No milestone'));
    await t.pump(const Duration(milliseconds: 500)); // the menu's opening animation
    await tap(find.text('New milestone…'));
    await t.pump(const Duration(milliseconds: 500));
    final fields = find.descendant(of: find.byType(MilestoneNameDialog), matching: find.byType(TextField));
    await t.enterText(fields.first, '2027 Q1');
    await t.enterText(fields.last, '2027-03');
    await tap(find.text('Plan'));
    expect(find.text('Not a date: YYYY-MM-DD'), findsOneWidget); // the dialog stays open
    await t.enterText(fields.last, '2027-03-31');
    await tap(find.text('Plan'));
    // optimistic: the milestone file and the plan are in memory before the writes return
    expect(ws.task('TASK-1')!.milestone, '2027 Q1');
    expect(ws.task('TASK-1')!.milestoneId, 'm-0');
    expect(find.descendant(of: find.byType(MilestoneMenu), matching: find.text('2027 Q1')), findsOneWidget);
    await t.runAsync(() => until(() => read(repo, 'backlog/tasks/task-1 - first.md').contains('milestone: 2027 Q1\nmilestone_id: m-0')));
    expect(read(repo, 'backlog/milestones/m-0 - 2027-q1.md'), contains('due_date: "2027-03-31"'));

    // Milestones view: 2027 Q1 holds 1-first; a right click moves it to v1 launch.
    await tap(find.textContaining('Milestones', findRichText: true).first);
    await tap(find.textContaining('2027 Q1', findRichText: true).first);
    final row = find.textContaining('1. first', findRichText: true).last;
    await t.tap(row, buttons: kSecondaryButton);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 500));
    await tap(find.text('Move to v1 launch'));
    expect(ws.task('TASK-1')!.milestone, 'v1 launch');
    await t.runAsync(() => until(() => read(repo, 'backlog/tasks/task-1 - first.md').contains('v1 launch')));
    expect(read(repo, 'backlog/tasks/task-1 - first.md'), isNot(contains('milestone_id'))); // v1 launch has no file

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      ws.dispose();
      s.dispose();
      await nvim.stop();
    });
  });
}
