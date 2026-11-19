import 'dart:async';

import '../backend/repo_backend.dart';
import '../timing/ui_timing.dart';
import 'action_failure.dart';
import 'session.dart';
import 'status_store.dart';

/// What an action did: its name, the error text, and the report both the notice
/// bar and the Log read.
class ActionResult {
  const ActionResult(
    this.name,
    this.error, {
    this.failure,
    this.origin,
    this.command,
    this.changed = 0,
  });

  final String name;
  final String? error;
  final ActionFailure? failure;
  final String? origin;
  final String? command;
  final int changed;

  bool get ok => error == null;
  String? get problem => failure?.summary;
}

/// Runs the actions on the repository one at a time, so two clicks cannot fight over the index.
/// An action may change the rows before git answers; when it fails, only its own rows are put
/// back. The store reloads after it.
class ActionQueue {
  ActionQueue(this.session, this.store);

  final Session session;
  final StatusStore store;
  Future<void> _tail = Future.value();

  /// The last 200 action reports, oldest first: what the Log shows.
  final List<ActionResult> reports = [];

  /// An action is waiting or running.
  bool get busy => store.pending > 0;

  /// Queue [action], timed as `<area>.<name>`.
  /// - [predict] changes the rows at once and [optimistic] whatever else the mode shows (its
  ///   selection); both happen before the action waits for its turn.
  /// - [settled] is awaited after the reload and before the timing ends: the mode's own follow-up
  ///   (it loads the selected diff).
  /// - [origin], [command], [params] and [changed] are kept in the result for the Log; on failure
  ///   they build the [ActionFailure].
  Future<ActionResult> run(
    String name,
    Future<void> Function(RepoBackend b) action, {
    String area = 'status',
    Prediction? predict,
    void Function()? optimistic,
    Future<void> Function()? settled,
    String? origin,
    String? command,
    Map<String, Object?> params = const {},
    int changed = 0,
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
      final result = ActionResult(
        name,
        err,
        failure: err == null
            ? null
            : ActionFailure.fromText(err, origin: origin ?? name, params: params, command: command),
        origin: origin ?? name,
        command: command,
        changed: changed,
      );
      reports.add(result);
      if (reports.length > 200) reports.removeAt(0);
      return result;
    });
    _tail = turn.then((_) {}, onError: (_) {});
    return turn;
  }
}
