import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    await state.ignoreSelected('${temp.path}/.gitignore');
    await until(() => !state.visible.any((row) => row.path == 'a.txt'));
    expect(await File('${temp.path}/.gitignore').readAsString(), contains('a.txt'));

    state.click(state.visible.indexWhere((row) => row.path == 'tracked.txt'));
    await state.deleteSelected();
    expect(removed.single, endsWith('tracked.txt'));
  });
}
