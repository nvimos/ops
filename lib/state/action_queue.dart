import 'dart:async';

import '../backend/repo_backend.dart';
import '../timing/ui_timing.dart';
import 'session.dart';
import 'status_store.dart';

/// What an action did: its name and the error text (with the backend's trace), or null.
class ActionResult {
  const ActionResult(this.name, this.error);
  final String name;
  final String? error;
  bool get ok => error == null;
}

/// Runs the actions on the repository one at a time, so two clicks cannot fight over the index.
/// An action may change the rows before git answers; when it fails, only its own rows are put
/// back. The store reloads after it.
class ActionQueue {
  ActionQueue(this.session, this.store);

  final Session session;
  final StatusStore store;
  Future<void> _tail = Future.value();

  /// An action is waiting or running.
  bool get busy => store.pending > 0;

  /// Queue [action], timed as `<area>.<name>`.
  /// - [predict] changes the rows at once and [optimistic] whatever else the mode shows (its
  ///   selection); both happen before the action waits for its turn.
  /// - [settled] is awaited after the reload and before the timing ends: the mode's own follow-up
  ///   (it loads the selected diff).
  Future<ActionResult> run(
    String name,
    Future<void> Function(RepoBackend b) action, {
    String area = 'status',
    Prediction? predict,
    void Function()? optimistic,
    Future<void> Function()? settled,
  }) {
    final span = UiTiming.instance.span('$area.$name');
    store.pending++;
    final undo = predict == null ? null : store.predict(predict);
    optimistic?.call();
    store.changed();
    if (predict != null || optimistic != null) span.markPainted();
    final turn = _tail.then((_) async {
      final err = await session.run(action);
      span.mark('git');
      if (err != null) store.undo(undo);
      store.pending--;
      store.changed();
      await store.refresh();
      if (settled != null) await settled();
      span.end();
      return ActionResult(name, err);
    });
    _tail = turn.then((_) {}, onError: (_) {});
    return turn;
  }
}
