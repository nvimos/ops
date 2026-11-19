import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../timing/ui_timing.dart';
import 'session.dart';

/// What git is expected to say after an action: the rows of the working tree, changed.
typedef Prediction = List<StatusFile> Function(List<StatusFile> files);

/// What one prediction replaced, to put exactly those rows back if the action fails.
class Undo {
  Undo._(this._replaced, this._removed);
  final Map<StatusFile, StatusFile> _replaced; // predicted row -> the row it replaced
  final List<StatusFile> _removed; // rows the prediction dropped
}

/// The status of the repository: the only owner of the file list. The modes that show files
/// (Changes, Add and Ignore) read it and keep only their own cursor, selection and filter.
///
/// It reloads on every git hint from the session. While an action runs ([pending]) a reload is
/// skipped: it could predate the action and flip a predicted move back; the action's own reload
/// follows.
class StatusStore extends ChangeNotifier {
  StatusStore(this.session) {
    session.gitChanged.addListener(refresh);
  }

  final Session session;
  Status? status;
  Branches? branches;

  /// The last reload's error (full text); the old [status] stays.
  String? error;

  /// Actions still waiting for git; the action queue counts them.
  int pending = 0;

  /// Bumps after every reload (also a failed one): what a mode looks at to follow the new rows.
  final refreshed = ValueNotifier<int>(0);

  int _gen = 0;
  bool _disposed = false;

  Future<void> refresh() => UiTiming.instance.time('status.refresh', _refresh);

  Future<void> _refresh() async {
    final b = session.backend;
    if (b == null || pending > 0) return;
    final gen = ++_gen;
    try {
      final (st, br) = await (b.status(), b.branches()).wait;
      if (gen != _gen || pending > 0 || _disposed) return;
      status = st;
      branches = br;
      error = null;
    } catch (e) {
      if (gen != _gen || _disposed) return;
      error = '$e';
    }
    refreshed.value++;
    notifyListeners();
  }

  /// Show [predict]'s rows now, before git answers. Returns what to undo, or null when nothing
  /// changed.
  Undo? predict(Prediction predict) {
    final st = status;
    if (st == null) return null;
    final next = predict(st.files);
    final replaced = <StatusFile, StatusFile>{};
    final kept = Set<StatusFile>.identity()..addAll(next);
    final removed = <StatusFile>[];
    final olds = Set<StatusFile>.identity()..addAll(st.files);
    for (var i = 0; i < st.files.length; i++) {
      final old = st.files[i];
      if (kept.contains(old)) continue;
      if (i < next.length && !olds.contains(next[i])) {
        replaced[next[i]] = old;
      } else {
        removed.add(old);
      }
    }
    status = st.withFiles(next);
    return replaced.isEmpty && removed.isEmpty ? null : Undo._(replaced, removed);
  }

  /// The backend went away or was swapped: nothing it said is true any more.
  void reset() {
    _gen++;
    status = null;
    branches = null;
    error = null;
    pending = 0;
    notifyListeners();
  }

  /// Put back the rows [undo] replaced or removed, and only those that still show the prediction.
  void undo(Undo? undo) {
    final st = status;
    if (undo == null || st == null) return;
    status = st.withFiles([for (final f in st.files) undo._replaced[f] ?? f, ...undo._removed]);
  }

  /// A mode changed what it shows around the store's rows (an optimistic move): rebuild.
  void changed() => notifyListeners();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    session.gitChanged.removeListener(refresh);
    refreshed.dispose();
    super.dispose();
  }
}
