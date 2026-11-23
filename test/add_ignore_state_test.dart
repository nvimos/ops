import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/local/local_backend.dart';
import 'package:nvimos_poc/state/add_ignore.dart';
import 'package:nvimos_poc/state/session.dart';

import 'support/local_temp_repo.dart';

Future<void> until(bool Function() done, {Duration timeout = const Duration(seconds: 8)}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw StateError('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('a cursor move only moves the cursor: the rows are built once per status and filter', () {
    final session = Session();
    addTearDown(session.dispose);
    session.store.status = Status({
      'files': [
        for (final n in ['c', 'a', 'b']) {'path': '$n.txt', 'index': '?', 'worktree': '?', 'untracked': true},
      ],
    });
    final state = AddIgnoreState(session);
    addTearDown(state.dispose);

    final rows = state.rows, visible = state.visible;
    expect(visible.map((r) => r.path), ['a.txt', 'b.txt', 'c.txt']);
    state.move(1);
    state.move(1);
    state.move(-1);
    expect(state.selected?.path, 'b.txt');
    expect(identical(state.rows, rows) && identical(state.visible, visible), isTrue, reason: 'no rebuild or sort per move');

    state.setFilter('c');
    expect(state.visible.map((r) => r.path), ['c.txt']);
    expect(identical(state.rows, rows), isTrue, reason: 'a filter keeps the rows');
    session.store.status = session.store.status!.withFiles(const []);
    expect(state.rows, isEmpty, reason: 'a new status builds them again');
  });

  test('all files: every tracked file in a Tracked section, once, kept across moves and same refreshes', () async {
    final session = Session();
    addTearDown(session.dispose);
    session.store.status = Status({
      'files': [
        {'path': 'b.txt', 'index': ' ', 'worktree': 'M', 'unstaged': true},
        {'path': 'new.txt', 'index': '?', 'worktree': '?', 'untracked': true},
      ],
    });
    var tracked = ['a.txt', 'b.txt', 'c.txt'];
    var reads = 0;
    final state = AddIgnoreState(session, trackedFiles: () async {
      reads++;
      return [...tracked];
    });
    addTearDown(state.dispose);
    expect(state.showTracked, isFalse);
    expect(state.rows.map((r) => r.path), ['b.txt', 'new.txt']);
    expect(reads, 0, reason: 'off: no ls-files');

    state.toggleTracked();
    await until(() => state.rows.length == 4);
    expect([for (final r in state.rows) '${r.section.name}:${r.path}'], [
      'changed:b.txt',
      'untracked:new.txt',
      'tracked:a.txt',
      'tracked:c.txt',
    ], reason: 'b.txt is changed, not listed twice');
    expect(session.prefs.flag(AddIgnoreState.allFilesPref, fallback: false), isTrue, reason: 'remembered');

    final rows = state.rows;
    state.move(1);
    state.move(1);
    expect(identical(state.rows, rows), isTrue, reason: 'a cursor move keeps the rows');
    session.store.refreshed.value++;
    await until(() => reads == 2);
    await Future<void>.delayed(Duration.zero);
    expect(identical(state.rows, rows), isTrue, reason: 'a refresh with the same files keeps them');

    tracked = ['a.txt', 'b.txt', 'c.txt', 'd.txt'];
    session.store.refreshed.value++;
    await until(() => state.rows.length == 5);

    state.toggleTracked();
    expect(state.rows.map((r) => r.path), ['b.txt', 'new.txt']);
  });

  test('all files reads git ls-files of the repository', () async {
    final temp = await TempRepo.make();
    await temp.write('kept.txt', 'k\n');
    await temp.write('sub/deep file.txt', 'd\n');
    await temp.git(['add', '.']);
    await temp.git(['commit', '-q', '-m', 'files']);
    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);
    final session = Session()..backend = backend;
    addTearDown(session.dispose);
    final state = AddIgnoreState(session);
    addTearDown(state.dispose);
    state.toggleTracked();
    await until(() => state.rows.length == 3);
    expect(state.rows.map((r) => r.path), ['.gitignore', 'kept.txt', 'sub/deep file.txt'], reason: 'TempRepo commits a .gitignore');
    expect(state.rows.every((r) => r.clean), isTrue);
  });

  test('a clean tracked row cannot be added, only untracked or ignored', () async {
    final session = Session();
    addTearDown(session.dispose);
    session.store.status = Status({'files': const []});
    final state = AddIgnoreState(session, trackedFiles: () async => ['a.txt']);
    addTearDown(state.dispose);
    state.toggleTracked();
    await until(() => state.rows.isNotEmpty);
    state.click(0);
    expect(state.rows.single.clean, isTrue);
    expect((await state.trackSelected()).error, 'nothing to add');
  });

  test('track, untrack, ignore and delete through the action queue', () async {
    final temp = await TempRepo.make();
    await temp.write('a.txt', 'a\n');
    await temp.write('tracked.txt', 'one\n');
    await temp.git(['add', 'tracked.txt']);
    await temp.git(['commit', '-q', '-m', 'tracked']);
    await temp.write('tracked.txt', 'two\n');

    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);
    final session = Session()..backend = backend;
    final removed = <String>[];
    final state = AddIgnoreState(session, remove: (paths) async => removed.addAll(paths));
    addTearDown(state.dispose);
    await until(() => state.visible.length >= 2);

    final aIndex = state.visible.indexWhere((row) => row.path == 'a.txt');
    state.click(aIndex);
    await state.trackSelected();
    await until(() => state.visible.any((row) => row.path == 'a.txt' && row.section == AddIgnoreSection.staged));

    state.click(state.visible.indexWhere((row) => row.path == 'a.txt' && row.section == AddIgnoreSection.staged));
    await state.untrackSelected();
    await until(() => state.visible.any((row) => row.path == 'a.txt' && row.section == AddIgnoreSection.untracked));

    state.click(state.visible.indexWhere((row) => row.path == 'a.txt'));
    await state.ignoreSelected(const IgnoreFileRef.gitignore('.gitignore'));
    await until(() => !state.visible.any((row) => row.path == 'a.txt'));
    expect(await File('${temp.path}/.gitignore').readAsString(), contains('a.txt'));

    state.click(state.visible.indexWhere((row) => row.path == 'tracked.txt'));
    await state.deleteSelected();
    expect(removed.single, endsWith('tracked.txt'));
  });

  test('the eye ignores a tracked row and stops tracking it, the file staying on disk', () async {
    final temp = await TempRepo.make();
    await temp.write('tracked.txt', 'one\n');
    await temp.git(['add', 'tracked.txt']);
    await temp.git(['commit', '-q', '-m', 'tracked']);
    await temp.write('tracked.txt', 'two\n');

    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);
    final session = Session()..backend = backend;
    final state = AddIgnoreState(session);
    addTearDown(state.dispose);
    await until(() => state.visible.any((row) => row.path == 'tracked.txt'));

    state.click(state.visible.indexWhere((row) => row.path == 'tracked.txt'));
    final result = await state.ignoreAndUntrackSelected(const IgnoreFileRef.gitignore('.gitignore'));
    expect(result.error, isNull);

    // The rule is written, the file is still there, and git no longer tracks it (the index holds
    // the deletion until it is committed).
    expect(await File('${temp.path}/.gitignore').readAsString(), contains('tracked.txt'));
    expect(await File('${temp.path}/tracked.txt').readAsString(), 'two\n');
    final listed = (await temp.git(['ls-files', '--', 'tracked.txt'])).stdout as String;
    expect(listed.trim(), isEmpty);
    await until(() => state.visible.any((row) => row.path == 'tracked.txt' && row.section == AddIgnoreSection.staged));
  });

  test('a folder row keeps its trailing slash in the name and its folder apart', () {
    // The backend lists untracked files one by one, but a directory path (from either backend) ends
    // in a slash; its base name must not come out empty.
    final file = StatusFile({'path': 'src/gen/', 'index': '?', 'worktree': '?', 'untracked': true});
    final row = AddIgnoreRow(file, AddIgnoreSection.untracked);
    expect(row.isDirectory, isTrue);
    expect(row.folder, 'src', reason: 'the folder column, without the trailing slash');
    expect(row.name, 'gen/', reason: 'a folder reads as a folder');
  });

  test('a file at the root has no folder and its plain name', () {
    final row = AddIgnoreRow(StatusFile({'path': 'a.txt', 'index': '?', 'worktree': '?', 'untracked': true}), AddIgnoreSection.untracked);
    expect(row.folder, '');
    expect(row.name, 'a.txt');
  });
}
