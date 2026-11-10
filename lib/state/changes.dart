import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import 'session.dart';

/// State of the Changes view: working tree vs HEAD, the selected file's diff, and actions.
class ChangesState extends ChangeNotifier {
  ChangesState(this.session) {
    session.gitChanged.addListener(refresh);
    refresh();
  }

  final Session session;
  Status? status;
  String? selected;
  bool selectedStaged = false;
  DiffFile? diff;
  String? error; // last action's error, for a snackbar
  bool busy = false;
  int _gen = 0;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<StatusFile> get staged => status?.files.where((f) => f.staged).toList() ?? [];
  List<StatusFile> get unstaged =>
      status?.files.where((f) => f.unstaged || f.untracked || f.conflicted).toList() ?? [];

  Future<void> refresh() async {
    final b = session.backend;
    if (b == null) return;
    final gen = ++_gen;
    try {
      final st = await b.status();
      if (gen != _gen) return;
      status = st;
      // Keep the selection if the file still has changes on that side; else pick another.
      final side = selectedStaged ? staged : unstaged;
      if (selected == null || !side.any((f) => f.path == selected)) {
        final other = selectedStaged ? unstaged : staged;
        if (selected != null && other.any((f) => f.path == selected)) {
          selectedStaged = !selectedStaged;
        } else if (unstaged.isNotEmpty) {
          selected = unstaged.first.path;
          selectedStaged = false;
        } else if (staged.isNotEmpty) {
          selected = staged.first.path;
          selectedStaged = true;
        } else {
          selected = null;
        }
      }
      diff = selected == null ? null : await b.diffFile(selected!, staged: selectedStaged);
      if (gen != _gen) return;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void select(String path, {required bool staged}) {
    selected = path;
    selectedStaged = staged;
    diff = null;
    notifyListeners();
    refresh();
  }

  /// Run an action, then refresh. Returns the error text, or null.
  Future<String?> act(Future<void> Function(Backend b) action) async {
    busy = true;
    notifyListeners();
    final err = await session.run(action);
    busy = false;
    await refresh();
    return err;
  }

  Future<String?> commit(String message) => act((b) => b.commit(message));

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    session.gitChanged.removeListener(refresh);
    super.dispose();
  }
}
