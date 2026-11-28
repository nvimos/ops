import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/backend/repo_backend.dart';
import 'package:nvimos_poc/local/local_backend.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'support/temp_dirs.dart';

/// A refresh's `diffFile` stays in flight until the test completes it, one future per call.
class _DiffHold implements RepoBackend {
  final calls = <_DiffCall>[];

  @override
  Future<DiffFile?> diffFile(String path, {required bool staged}) {
    final call = _DiffCall(path, staged);
    calls.add(call);
    return call.future;
  }

  /// A watcher refresh must not finish and start another reconcile behind the test.
  @override
  Future<Status> status() => Completer<Status>().future;

  @override
  Future<Branches> branches() => Completer<Branches>().future;

  @override
  Stream<NvimEvent> get events => const Stream.empty();

  @override
  Future<void> get done => Completer<void>().future;

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName} is not used here');
}

class _DiffCall {
  _DiffCall(this.path, this.staged);
  final String path;
  final bool staged;
  final _done = Completer<DiffFile?>();
  Future<DiffFile?> get future => _done.future;
  void complete(DiffFile? diff) => _done.complete(diff);
}

class _Open {
  _Open(this.session, this.state, this.gate);
  final Session session;
  final ChangesState state;
  final _DiffHold gate;
  var _stateGone = false;

  void closeState() {
    if (_stateGone) return;
    _stateGone = true;
    state.dispose();
  }
}

/// Status is loaded from a real local repo, then [Session.backend] is the hold.
/// The watcher is closed first so a disk event cannot start a reconcile of its own.
Future<_Open> _open() async {
  Prefs.baseOverride = keepForCleanup(Directory.systemTemp.createTempSync('nvimos_appdata_')).path;
  addTearDown(() => Prefs.baseOverride = null);

  final repo = await makeRepo();
  await Directory('${repo.path}/lib').create();
  await File('${repo.path}/lib/cart.dart').writeAsString('cart\n');
  await File('${repo.path}/lib/tax.dart').writeAsString('tax\n');

  final session = Session();
  addTearDown(session.dispose);
  addTearDown(session.disconnect);
  await session.openFolder(repo.path);
  expect(session.conn, Conn.connected, reason: session.error);

  final state = ChangesState(session);
  final open = _Open(session, state, _DiffHold());
  addTearDown(open.closeState);
  await until(() => state.unstaged.map((f) => f.path).join(',') == 'lib/cart.dart,lib/tax.dart' && state.diff != null);
  expect(state.selected, 'lib/cart.dart');
  expect(state.selectedStaged, isFalse);

  await (session.backend! as LocalBackend).watcher?.close();
  await Future<void>.delayed(Duration.zero);
  await state.refresh();
  session.backend = open.gate;
  await Future<void>.delayed(Duration.zero);
  expect(open.gate.calls, isEmpty);
  return open;
}

DiffFile _diff(String path) => DiffFile({
  'path': path,
  'old_path': path,
  'status': 'M',
  'additions': 1,
  'deletions': 0,
  'hunks': [
    {
      'header': '@@ -1 +1 @@',
      'old_start': 1,
      'old_count': 1,
      'new_start': 1,
      'new_count': 1,
      'section': '',
      'lines': [
        {'kind': 'add', 'text': path, 'new': 1},
      ],
    },
  ],
});

void main() {
  test('a reconcile for the previous file does not paint after a click', () async {
    final open = await _open();
    final cart = _diff('lib/cart.dart');
    open.state.store.refreshed.value++;
    final call = open.gate.calls.single;
    expect(call.path, 'lib/cart.dart');
    expect(call.staged, isFalse);

    open.state.select('lib/tax.dart', staged: false);
    expect(open.state.diff, isNull);
    call.complete(cart);
    await call.future;

    expect(open.state.selected, 'lib/tax.dart');
    expect(open.state.diff, isNot(same(cart)));
    expect(open.state.diff?.path, isNot('lib/cart.dart'));
    // select() waits 120 ms before its own load. Closing now cancels that timer, so it cannot
    // paint cart afterwards.
    open.closeState();
  });

  test('a reconcile that finishes while that file is still selected stores its diff', () async {
    final open = await _open();
    open.state.store.refreshed.value++;
    final call = open.gate.calls.single;
    expect(call.path, 'lib/cart.dart');
    expect(call.staged, isFalse);

    final incoming = _diff(call.path);
    call.complete(incoming);
    await call.future;
    expect(open.state.selected, 'lib/cart.dart');
    expect(open.state.diff, same(incoming));
  });

  test('a newer reconcile drops the older diff', () async {
    final open = await _open();
    open.state.store.refreshed.value++;
    final older = open.gate.calls.single;
    open.state.store.refreshed.value++;
    final newer = open.gate.calls[1];
    expect(older.path, 'lib/cart.dart');
    expect(newer.path, 'lib/cart.dart');

    final oldDiff = _diff(older.path);
    final newDiff = _diff(newer.path);
    older.complete(oldDiff);
    await older.future;
    expect(open.state.diff, isNot(same(oldDiff)));

    newer.complete(newDiff);
    await newer.future;
    expect(open.state.selected, 'lib/cart.dart');
    expect(open.state.diff, same(newDiff));
  });

  test('a reconcile for the other side does not paint after the side changes', () async {
    final open = await _open();
    final cart = _diff('lib/cart.dart');
    open.state.store.refreshed.value++;
    final call = open.gate.calls.single;
    expect(call.path, 'lib/cart.dart');
    expect(call.staged, isFalse);

    open.state.select('lib/cart.dart', staged: true);
    call.complete(cart);
    await call.future;

    expect(open.state.selected, 'lib/cart.dart');
    expect(open.state.selectedStaged, isTrue);
    expect(open.state.diff, isNot(same(cart)));
    open.closeState();
  });
}
