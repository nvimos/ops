import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/backend/models.dart';
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

/// An open pane with its first load and the later untracked pass done.
Future<IgnorePaneState> openPane(AddIgnoreState add) async {
  final pane = IgnorePaneState(add);
  addTearDown(pane.dispose);
  await until(() => !pane.loading && pane.selected != null);
  await Future<void>.delayed(const Duration(milliseconds: 80));
  return pane;
}

const project = IgnoreFileRef.gitignore('.gitignore');
const nested = IgnoreFileRef.gitignore('src/.gitignore');

void main() {
  test('the dialog builds the rules for the scope and the file, and writes them', () async {
    final (_, add, repo) = await localRepo();
    add.click(0); // notes/n.txt
    add.click(1, shift: true); // .. src/a.log
    final choice = (await IgnoreChoice.forSelection(add))!;

    expect(choice.paths, ['notes/n.txt', 'src/a.log']);
    expect(choice.targets.map((t) => t.kind), [
      IgnoreTargetKind.folderGitignore,
      IgnoreTargetKind.projectGitignore,
      IgnoreTargetKind.localExclude,
    ]);
    expect(choice.targets, everyElement(predicate<IgnoreTarget>((t) => !t.path.startsWith('/'))));
    choice.setTarget(1); // the project .gitignore
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
    expect(add.lastIgnoreEffect?.lost, greaterThan(0), reason: 'the rows the rules cover left the list');
    // The new .gitignore is an untracked row of its own; the three logs are what leave.
    await until(() => add.rows.length == 1 && add.rows.single.path == '.gitignore');
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

  test('the pane lists every .gitignore, the project file first, and every line as it is', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/.gitignore').writeAsString('# rules\n\n/src/old/\n');
    await File('${repo.path}/src/.gitignore').writeAsString('*.tmp\n');
    await git(repo, ['add', '.gitignore', 'src/.gitignore']);

    final pane = await openPane(add);
    expect(pane.files.first.path, '.gitignore');
    expect(IgnorePaneState.labelOf(pane.files.first), 'project .gitignore');
    expect(pane.files.map((f) => f.path), containsAll(['.gitignore', 'src/.gitignore']));
    expect(pane.selected!.path, '.gitignore');
    expect(pane.lines, ['# rules', '', '/src/old/'], reason: 'comments and blank lines are shown, no numbers');

    final loads = pane.loads;
    await pane.pick(nested);
    expect(pane.selected!.path, 'src/.gitignore');
    expect(pane.lines, ['*.tmp']);
    expect(pane.loads, loads, reason: 'picking a file reads only that file');
  });

  test('the list keeps the session pick and never follows the cursor', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/.gitignore').writeAsString('/x\n');
    await File('${repo.path}/src/.gitignore').writeAsString('*.tmp\n');
    await git(repo, ['add', '.gitignore', 'src/.gitignore']);
    final pane = await openPane(add);
    await pane.pick(nested);
    await until(() => pane.lines.isNotEmpty);

    final loads = pane.loads, reads = pane.reads;
    for (final path in ['notes/n.txt', 'src/a.log', 'src/b.log', 'notes/n.txt']) {
      add.click(add.visible.indexWhere((r) => r.path == path));
    }
    expect(pane.selected!.path, 'src/.gitignore');
    expect(pane.loads, loads, reason: 'a cursor move reads no file');
    expect(pane.reads, reads);
    expect(pane.governing, contains('.gitignore'), reason: 'the project file governs every folder');
  });

  test('a write selects its file and centres the first new rule; a duplicate does not scroll', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/.gitignore').writeAsString('/x\n');
    await File('${repo.path}/src/.gitignore').writeAsString('*.tmp\n');
    await git(repo, ['add', '.gitignore', 'src/.gitignore']);
    final pane = await openPane(add);
    expect(pane.selected!.path, '.gitignore');

    final writes = await add.ignoreWith(nested, ['/a.log'], covered: const []);
    expect(writes.error, isNull, reason: writes.error);
    await until(() => pane.selected!.path == 'src/.gitignore' && pane.centreLine > 0);
    expect(pane.lines[pane.centreLine - 1], '/a.log');
    expect(pane.lineCursor, pane.centreLine);

    final request = pane.centreRequest;
    final reads = pane.reads;
    await add.ignoreWith(nested, ['/a.log'], covered: const []);
    await until(() => pane.reads > reads);
    expect(pane.selected!.path, 'src/.gitignore', reason: 'the write selects its file even when it is a duplicate');
    expect(pane.centreRequest, request, reason: 'nothing new was written: no scroll');
  });

  test('Delete removes the line and Undo puts it back; Undo refuses a changed file', () async {
    final (_, add, repo) = await localRepo();
    final file = File('${repo.path}/.gitignore');
    await file.writeAsString('*.tmp\n/src/old/\n');
    final pane = await openPane(add);
    await until(() => pane.lines.length == 2);

    final edit = await pane.deleteLine(1);
    expect(edit.ok, isTrue, reason: edit.refusal);
    expect(await file.readAsString(), '/src/old/\n');
    final undone = await edit.undo!();
    expect(undone.ok, isTrue, reason: undone.refusal);
    expect(await file.readAsString(), '*.tmp\n/src/old/\n');

    final again = await pane.deleteLine(1);
    expect(again.ok, isTrue);
    await file.writeAsString('# changed elsewhere\n');
    final refused = await again.undo!();
    expect(refused.ok, isFalse);
    expect(refused.refusal, contains('changed'));
  });

  test('Dirname moves the rule up, or removes it when the parent is already there, and Undo restores', () async {
    final (_, add, repo) = await localRepo();
    final file = File('${repo.path}/.gitignore');
    await file.writeAsString('/src/old/deep/\n');
    final pane = await openPane(add);
    await until(() => pane.lines.isNotEmpty);

    final edit = await pane.dirnameLine(1);
    expect(edit.ok, isTrue, reason: edit.refusal);
    expect(await file.readAsString(), contains('/src/old/'));
    final undone = await edit.undo!();
    expect(undone.ok, isTrue, reason: undone.refusal);
    expect(await file.readAsString(), '/src/old/deep/\n');

    await file.writeAsString('/src/\n/src/a.log\n');
    await pane.load();
    await until(() => pane.lines.length == 2 && pane.lines.last == '/src/a.log');
    final removed = await pane.dirnameLine(2);
    expect(removed.ok, isTrue, reason: removed.refusal);
    expect(await file.readAsString(), '/src/\n');
    final restored = await removed.undo!();
    expect(restored.ok, isTrue, reason: restored.refusal);
    expect(await file.readAsString(), '/src/\n/src/a.log\n');
  });

  test('Flip toggles the leading ! and Undo restores the old line', () async {
    final (_, add, repo) = await localRepo();
    final file = File('${repo.path}/.gitignore');
    await file.writeAsString('/src/a.log\n');
    final pane = await openPane(add);
    await until(() => pane.lines.isNotEmpty);

    final edit = await pane.flipLine(1);
    expect(edit.ok, isTrue, reason: edit.refusal);
    expect(await file.readAsString(), '!/src/a.log\n');
    final undone = await edit.undo!();
    expect(undone.ok, isTrue, reason: undone.refusal);
    expect(await file.readAsString(), '/src/a.log\n');
  });

  test('the effect notice says the rows that came back after a rule was deleted', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/.gitignore').writeAsString('/src/a.log\n');
    await until(() => !add.rows.any((r) => r.path == 'src/a.log'));
    final pane = await openPane(add);
    await until(() => pane.lines.isNotEmpty);

    final edit = await pane.deleteLine(1);
    expect(edit.ok, isTrue, reason: edit.refusal);
    expect(edit.message, contains('back in the list'));
    expect(add.rows.any((r) => r.path == 'src/a.log'), isTrue, reason: 'the row came back without an extra git call');
  });

  test('the marker shows the files that govern the cursor folder and leaves the selection alone', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/.gitignore').writeAsString('/x\n');
    await File('${repo.path}/src/.gitignore').writeAsString('*.tmp\n');
    await git(repo, ['add', '.gitignore', 'src/.gitignore']);
    final pane = await openPane(add);
    final picked = pane.selected;

    add.click(add.visible.indexWhere((r) => r.path == 'src/b.log'));
    expect(pane.governing, containsAll(['.gitignore', 'src/.gitignore']));
    expect(pane.selected, picked, reason: 'the marker never moves the selection');

    add.click(add.visible.indexWhere((r) => r.path == 'notes/n.txt'));
    expect(pane.governing, {'.gitignore'});
    expect(pane.selected, picked);
  });

  test('hidden, the pane reads nothing and marks itself stale until shown', () async {
    final (_, add, repo) = await localRepo();
    await File('${repo.path}/.gitignore').writeAsString('/x\n');
    final pane = await openPane(add);
    pane.setVisible(false);
    expect(pane.stale, isTrue);

    final loads = pane.loads;
    await File('${repo.path}/.gitignore').writeAsString('/x\n/y\n');
    await add.store.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(pane.loads, loads, reason: 'a refresh while hidden reads nothing');
    expect(pane.stale, isTrue);

    pane.setVisible(true);
    await until(() => pane.loads > loads);
    expect(pane.stale, isFalse);
  });

  test('a tracked row can be ignored too, and the project .gitignore is the default target', () async {
    final (_, add, repo) = await localRepo();
    await git(repo, ['add', 'notes/n.txt']);
    await until(() => add.rows.any((r) => r.path == 'notes/n.txt' && !r.untracked));
    add.click(add.visible.indexWhere((r) => r.path == 'notes/n.txt'));
    final choice = await IgnoreChoice.forSelection(add);
    expect(choice, isNotNull, reason: 'Purrage opens the dialog for a tracked row');
    expect(choice!.paths, ['notes/n.txt']);
    expect(choice.target.kind, IgnoreTargetKind.projectGitignore);
    expect(choice.summary, '1 file → 1 rule');
  });

  test('connected to Neovim, the dialog works on the root Neovim reports', () async {
    final repo = await makeRepo();
    await File('${repo.path}/x.log').writeAsString('x');
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    addTearDown(s.dispose);
    addTearDown(s.disconnect);
    await s.connect();
    final add = AddIgnoreState(s);
    addTearDown(add.dispose);
    await until(() => add.rows.any((r) => r.path == 'x.log'));
    add.click(add.visible.indexWhere((r) => r.path == 'x.log'));
    expect(s.repo?.root, isNotNull, reason: 'Neovim reports the repository root');
    expect(add.actionRows.map((r) => r.path), ['x.log']);

    final choice = await IgnoreChoice.forSelection(add);
    expect(choice, isNotNull, reason: 'a Neovim session has no LocalBackend, but the backend holds the ignore files');
    final result = await choice!.apply();
    expect(result.error, isNull, reason: result.error);
    expect(await File('${repo.path}/.gitignore').readAsString(), contains('/x.log'));
  });

  test('a folder row offers a .gitignore inside it, which ignores what is below it', () async {
    final (_, add, repo) = await localRepo();
    await Directory('${repo.path}/build').create();
    await File('${repo.path}/build/x.bin').writeAsString('x');
    final r = add.repo!;

    final targets = IgnoreRules.targets(
      repoPath: repo.path,
      gitignoreFiles: await r.gitignoreFiles(),
      localExclude: await r.localExcludePath(),
      path: 'build/',
    );
    final inside = targets.first;
    expect(inside.kind, IgnoreTargetKind.folderGitignore);
    expect(inside.dir, 'build');
    expect(inside.path, endsWith('/build/.gitignore'));
    expect(inside.exists, isFalse, reason: 'the dialog says it will be made');
    expect(IgnoreRules.targets(
      repoPath: repo.path,
      gitignoreFiles: await r.gitignoreFiles(),
      localExclude: await r.localExcludePath(),
      path: 'build/',
    ).map((t) => t.kind), [
      IgnoreTargetKind.folderGitignore,
      IgnoreTargetKind.projectGitignore,
      IgnoreTargetKind.localExclude,
    ], reason: 'no parent folder at the root: inside, project, exclude');

    // A rule written inside the folder ignores all of it, and the file appears.
    expect(IgnoreRules.pattern(scope: IgnoreScope.folder, targetDir: inside.dir, path: 'build/'), '*');
    expect(IgnoreRules.pattern(scope: IgnoreScope.file, targetDir: inside.dir, path: 'build/'), '*');

    await r.appendIgnoreLine(inside.path, '*');
    expect(await File(inside.path).readAsString(), contains('*'));
  });

  testWidgets('the dialog shows the rules, and the scope and target keys change them', (t) async {
    final choice = (await t.runAsync(() async {
      final (_, add, _) = await localRepo();
      add.click(1); // src/a.log
      return (await IgnoreChoice.forSelection(add))!;
    }))!;
    await t.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: IgnoreDialog(choice: choice))));
    await t.pump();

    expect(find.text('Ignore src/a.log'), findsOneWidget);
    expect(find.text('project .gitignore'), findsOneWidget);
    expect(find.text('.gitignore in src'), findsOneWidget);
    expect(find.text('/src/a.log'), findsOneWidget);
    expect(find.text('1 file → 1 rule'), findsOneWidget);
    expect(
      find.text('does not exist yet: writing a rule creates it'),
      findsNWidgets(2),
      reason: 'neither .gitignore is there yet; .git/info/exclude is',
    );

    await t.tap(find.text('this extension'));
    await t.pump();
    expect(find.text('*.log'), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.digit3);
    await t.pump();
    expect(choice.scope, IgnoreScope.folder);
    expect(find.text('/src/'), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.keyK); // up: the .gitignore in src
    await t.pump();
    expect(choice.target.kind, IgnoreTargetKind.folderGitignore);
  });

  testWidgets('the pane shows the two panes, with the hover buttons on the lines', (t) async {
    final pane = (await t.runAsync(() async {
      final (_, add, repo) = await localRepo();
      await File('${repo.path}/.gitignore').writeAsString('# a comment\n*.tmp\n');
      await File('${repo.path}/src/.gitignore').writeAsString('*.log\n');
      final pane = IgnorePaneState(add);
      addTearDown(pane.dispose);
      await until(() => !pane.loading && pane.selected != null && pane.lines.length == 2);
      await until(() => pane.files.length >= 2);
      return pane;
    }))!;
    final filesFocus = FocusNode(debugLabel: 'ignore files');
    final linesFocus = FocusNode(debugLabel: 'ignore lines');
    addTearDown(filesFocus.dispose);
    addTearDown(linesFocus.dispose);
    await t.binding.setSurfaceSize(const Size(900, 500));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SizedBox(width: 360, height: 400, child: IgnorePane(state: pane, filesFocus: filesFocus, linesFocus: linesFocus)),
        ),
      ),
    );
    await t.pump();

    expect(find.text('project .gitignore'), findsOneWidget);
    expect(find.text('src'), findsOneWidget);
    expect(find.text('# a comment'), findsOneWidget);
    expect(find.text('*.tmp'), findsOneWidget);

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.text('*.tmp')));
    await t.pump();
    expect(find.byTooltip('Delete this line'), findsOneWidget);
    expect(find.byTooltip('no folder above this rule'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
