import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/local/git_repo.dart';
import 'package:nvimos_poc/local/ignore_rules.dart';
import 'package:nvimos_poc/state/add_ignore.dart';
import 'package:nvimos_poc/state/ignore_choice.dart';
import 'package:nvimos_poc/state/ignore_pane.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/ignore_dialog.dart';
import 'package:nvimos_poc/ui/ignore_pane.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

/// A local session over a repository with untracked files in several folders.
Future<(Session, AddIgnoreState, Directory)> localRepo() async {
  final repo = await makeRepo();
  await Directory('${repo.path}/src').create();
  await Directory('${repo.path}/notes').create();
  await File('${repo.path}/src/a.log').writeAsString('a');
  await File('${repo.path}/src/b.log').writeAsString('b');
  await File('${repo.path}/notes/n.txt').writeAsString('n');
  final s = Session();
  addTearDown(s.dispose);
  addTearDown(s.disconnect); // runs first: the watcher lets go of the folder before it is deleted
  await s.openFolder(repo.path);
  expect(s.conn, Conn.connected, reason: s.error);
  final add = AddIgnoreState(s);
  addTearDown(add.dispose);
  await until(() => add.rows.length == 3);
  return (s, add, repo);
}

void main() {
  test('the dialog builds the rules for the scope and the file, and writes them', () async {
    final (_, add, repo) = await localRepo();
    add.click(0); // notes/n.txt
    add.click(1, shift: true); // .. src/a.log
    final choice = (await IgnoreChoice.forSelection(add))!;

    expect(choice.paths, ['notes/n.txt', 'src/a.log']);
    expect(choice.targets.map((t) => t.kind), [
      IgnoreTargetKind.folderGitignore,
      IgnoreTargetKind.rootGitignore,
      IgnoreTargetKind.localExclude,
      IgnoreTargetKind.globalIgnore,
    ]);
    choice.setTarget(1); // the root .gitignore
    expect(choice.patterns, ['/notes/n.txt', '/src/a.log']);
    expect(choice.covered, ['notes/n.txt', 'src/a.log']);

    choice.setScope(IgnoreScope.extension);
    expect(choice.patterns, ['*.txt', '*.log']);
    expect(choice.covered, containsAll(['notes/n.txt', 'src/a.log', 'src/b.log']), reason: '*.log reaches the file next to it');

    choice.setScope(IgnoreScope.folder);
    expect(choice.patterns, ['/notes/', '/src/']);

    choice.setScope(IgnoreScope.extension);
    final result = await choice.apply();
    expect(result.error, isNull, reason: result.error);
    expect(await File('${repo.path}/.gitignore').readAsString(), allOf(contains('*.txt'), contains('*.log')));
    await until(() => add.rows.isEmpty);
  });

  test('a scope that names nothing says so, and nothing is written', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/Makefile').writeAsString('all:');
    await until(() => add.rows.length == 4);
    add.click(0); // Makefile has no extension
    final choice = (await IgnoreChoice.forSelection(add))!;
    choice.setScope(IgnoreScope.extension);
    expect(choice.patterns, isEmpty);
    expect(choice.problem, contains('names nothing'));
  });

  test('the pane follows the cursor with one lookup at rest, and edits the rules', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/.gitignore').writeAsString('*.tmp\n# a comment\n/src/old/\n');
    final pane = IgnorePaneState(add, delay: const Duration(milliseconds: 60));
    addTearDown(pane.dispose);

    // the file just written reaches the list through the watcher: let that settle first
    await until(() => pane.info != null);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final before = pane.lookups;
    for (final i in [1, 2, 1, 0, 2]) {
      add.click(i); // a walk over the rows: no lookup while the cursor moves
    }
    expect(pane.lookups, before);
    await until(() => pane.info?.path == add.selected?.path && !pane.loading);
    expect(pane.lookups, before + 1, reason: 'one lookup once the cursor rested');
    final root = pane.info!.files.firstWhere((f) => f.target.kind == IgnoreTargetKind.rootGitignore);
    expect(root.lines.map((l) => l.text), ['*.tmp', '/src/old/'], reason: 'comments are not rules');
    expect(pane.info!.match, isNull);

    final rule = root.lines.last;
    expect(pane.canMoveUp(rule), isTrue);
    expect(await pane.ruleOneFolderUp(root, rule), isTrue, reason: '/src/old/ -> /src/ is a real parent');
  });

  test('a rule can be deleted, or moved one folder up', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/.gitignore').writeAsString('*.tmp\n/src/old/deep/\n');
    final pane = IgnorePaneState(add, delay: const Duration(milliseconds: 20));
    addTearDown(pane.dispose);
    await until(() => pane.info != null);
    var root = pane.info!.files.firstWhere((f) => f.target.kind == IgnoreTargetKind.rootGitignore);

    expect(await pane.ruleOneFolderUp(root, root.lines.last), isTrue);
    expect(await File('${repo.path}/.gitignore').readAsString(), '*.tmp\n/src/old/\n');
    await until(() => pane.info!.files.first.lines.isNotEmpty || true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    root = pane.info!.files.firstWhere((f) => f.target.kind == IgnoreTargetKind.rootGitignore);

    expect(await pane.deleteRule(root, root.lines.first), isTrue);
    expect(await File('${repo.path}/.gitignore').readAsString(), '/src/old/\n');
    expect(await pane.deleteRule(root, root.lines.first), isFalse, reason: 'the file changed since it was read');
  });

  testWidgets('the dialog shows the rules and the rows they cover, and the choices change them', (t) async {
    final choice = (await t.runAsync(() async {
      final (_, add, _) = await localRepo();
      add.click(1); // src/a.log
      final c = (await IgnoreChoice.forSelection(add))!;
      c.setTarget(1);
      return c;
    }))!;
    await t.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: IgnoreDialog(choice: choice))));
    await t.pump();

    expect(find.text('Ignore a.log'), findsOneWidget);
    expect(find.text('+ /src/a.log'), findsOneWidget);
    expect(find.textContaining('takes 1 row off the list: a.log'), findsOneWidget);

    await t.tap(find.text('Every file like it'));
    await t.pump();
    expect(find.text('+ *.log'), findsOneWidget);
    expect(find.textContaining('takes 2 rows off the list'), findsOneWidget);

    await t.tap(find.text('Its folder'));
    await t.pump();
    expect(find.text('+ /src/'), findsOneWidget);
  });

  testWidgets('the pane shows the ignore files of the cursor row and moves with the cursor', (t) async {
    final session = Session();
    addTearDown(session.dispose);
    session.store.status = Status({
      'files': [
        {'path': 'a.log', 'index': '?', 'worktree': '?', 'untracked': true},
        {'path': 'b.txt', 'index': '?', 'worktree': '?', 'untracked': true},
      ],
    });
    final add = AddIgnoreState(session);
    addTearDown(add.dispose);
    const root = IgnoreTarget(kind: IgnoreTargetKind.rootGitignore, label: 'root', path: 'C:/r/.gitignore', dir: '', exists: true);
    final asked = <String>[];
    final pane = IgnorePaneState(
      add,
      delay: const Duration(milliseconds: 50),
      lookup: (p) async {
        asked.add(p);
        final match = p == 'a.log' ? const IgnoreMatch(source: 'C:/r/.gitignore', line: 1, pattern: '*.log', path: 'a.log') : null;
        return IgnoreInfo(p, [
          const IgnoreFileView(root, [IgnoreLine(1, '*.log'), IgnoreLine(2, '/build/x/')]),
        ], match);
      },
    );
    addTearDown(pane.dispose);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: IgnorePane(state: pane))));
    await t.pump(const Duration(milliseconds: 100));

    expect(find.text('a.log'), findsOneWidget);
    expect(find.textContaining('Ignored by *.log'), findsOneWidget);
    expect(find.text('/build/x/'), findsOneWidget);

    add.move(1);
    add.move(-1);
    add.move(1);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('b.txt'), findsOneWidget);
    expect(find.text('No rule ignores it.'), findsOneWidget);
    expect(asked, ['a.log', 'b.txt'], reason: 'one lookup per resting place, not per key');

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.text('/build/x/')));
    await t.pump();
    expect(find.byTooltip('Move the rule one folder up'), findsOneWidget);
    expect(find.byTooltip('Delete this rule'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
