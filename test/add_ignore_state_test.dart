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
