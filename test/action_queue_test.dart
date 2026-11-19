import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/local_backend.dart';
import 'package:nvimos_poc/state/action_queue.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/state/status_store.dart';

import 'support/local_temp_repo.dart';

void main() {
  test('a failure reports its origin, command and git text, and reaches the log', () async {
    final temp = await TempRepo.make();
    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);
    final session = Session()..backend = backend;
    final store = StatusStore(session);
    await store.refresh();
    final actions = ActionQueue(session, store);

    final result = await actions.run(
      'stage',
      (b) async => throw Exception('git says no'),
      origin: 'Changes.stage -> LocalBackend.stage',
      command: 'git add -- a.txt',
      params: {'path': 'a.txt'},
      changed: 1,
    );

    expect(result.ok, isFalse);
    expect(result.changed, 1);
    expect(result.failure!.summary, contains('git says no'));
    expect(result.failure!.detail, contains('origin: Changes.stage -> LocalBackend.stage'));
    expect(result.failure!.detail, contains('command: git add -- a.txt'));
    expect(result.failure!.detail, contains('path: a.txt'));
    expect(actions.reports.single, same(result));
  });

  test('actions run one at a time in queue order', () async {
    final temp = await TempRepo.make();
    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);
    final session = Session()..backend = backend;
    final actions = ActionQueue(session, StatusStore(session));
    final order = <String>[];
    final first = Completer<void>();

    final a = actions.run('a', (b) async {
      order.add('a');
      await first.future;
    });
    final b = actions.run('b', (b) async => order.add('b'));
    await Future<void>.delayed(Duration.zero);
    expect(order, ['a']);
    first.complete();
    await Future.wait([a, b]);
    expect(order, ['a', 'b']);
  });

  test('a refresh waits while an action is pending', () async {
    final temp = await TempRepo.make();
    final backend = await LocalBackend.open(temp.path);
    addTearDown(backend.close);
    final session = Session()..backend = backend;
    final store = StatusStore(session);
    await store.refresh();
    final actions = ActionQueue(session, store);
    final hold = Completer<void>();

    final running = actions.run('hold', (b) async => hold.future);
    await Future<void>.delayed(Duration.zero);
    final before = store.status;
    await store.refresh();
    expect(store.status, same(before));
    hold.complete();
    await running;
  });
}
