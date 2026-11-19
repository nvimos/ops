import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/state/status_store.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

Map<String, Object?> row(String path) => {'path': path, 'index': ' ', 'worktree': 'M', 'unstaged': true};

void main() {
  group('predict and undo', () {
    late Session s;
    late StatusStore store;

    setUp(() {
      s = Session();
      store = s.store;
      store.status = Status({
        'branch': 'main',
        'files': [row('a.txt'), row('b.txt')],
      });
    });
    tearDown(() => s.dispose());

    test('a prediction shows at once and undo puts back only the rows it changed', () {
      final undo = store.predict((files) => [for (final f in files) f.path == 'a.txt' ? f.moved(toStaged: true) : f]);
      expect(store.status!.files.first.staged, isTrue);

      // a later action changed b.txt meanwhile; undoing the first one must not touch it
      store.status = store.status!.withFiles([store.status!.files.first, store.status!.files.last.moved(toStaged: true)]);
      store.undo(undo);
      expect(store.status!.files.first.staged, isFalse);
      expect(store.status!.files.last.staged, isTrue);
    });

    test('a prediction that drops rows gets them back', () {
      final undo = store.predict((_) => []);
      expect(store.status!.files, isEmpty);
      store.undo(undo);
      expect(store.status!.files.map((f) => f.path), unorderedEquals(['a.txt', 'b.txt']));
    });

    test('a prediction that changes nothing has nothing to undo', () {
      expect(store.predict((files) => files), isNull);
    });
  });

  test('two mode states over one store see the same rows after an action', () async {
    final repo = await makeRepo();
    await File('${repo.path}/a.txt').writeAsString('changed\n');
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    addTearDown(s.dispose);
    await s.connect();
    final one = ChangesState(s), two = ChangesState(s);
    addTearDown(one.dispose);
    addTearDown(two.dispose);
    await until(() => one.unstaged.length == 1 && two.unstaged.length == 1);
    expect(identical(one.store, two.store), isTrue);

    final first = one.moveFile('a.txt', staged: false);
    expect(two.staged.map((f) => f.path), ['a.txt'], reason: 'the other state sees the move at once');
    expect(s.actions.busy, isTrue);
    expect(await first, isNull);
    expect(s.actions.busy, isFalse);
    expect(two.staged.map((f) => f.path), ['a.txt']);
    expect(one.unstaged, isEmpty);

    // the queue runs actions one after the other
    final order = <String>[];
    final a = s.actions.run('unstage', (b) async {
      order.add('unstage start');
      await b.unstage('a.txt');
      order.add('unstage end');
    });
    final c = s.actions.run('stage', (b) async {
      order.add('stage start');
      await b.stage('a.txt');
      order.add('stage end');
    });
    // (git may refuse one of them while a status reload holds the index lock; the order is the point)
    await a;
    await c;
    expect(order, ['unstage start', 'unstage end', 'stage start', 'stage end']);
  });
}
