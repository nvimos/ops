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

Future<(TestNvim, Session, Workspace, Directory)> open() async {
  final repo = await milestoneRepo();
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
    await t.enterText(find.descendant(of: find.byType(MilestoneNameDialog), matching: find.byType(TextField)), '2027 Q1');
    await tap(find.text('Plan'));
    expect(ws.task('TASK-1')!.milestone, '2027 Q1'); // optimistic: in memory before the write returns
    expect(find.descendant(of: find.byType(MilestoneMenu), matching: find.text('2027 Q1')), findsOneWidget);
    await t.runAsync(() => until(() => read(repo, 'backlog/tasks/task-1 - first.md').contains('2027 Q1')));

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

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      ws.dispose();
      s.dispose();
      await nvim.stop();
    });
  });
}
