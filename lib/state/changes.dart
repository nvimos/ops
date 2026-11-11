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
  String? error; // the last refresh's error (full text); the view shows it in place of the diff
  bool busy = false;
  int _gen = 0;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<StatusFile> get staged => status?.files.where((f) => f.staged).toList() ?? [];
  List<StatusFile> get unstaged => status?.files.where((f) => f.unstaged || f.untracked || f.conflicted).toList() ?? [];

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
      error = null;
    } catch (e) {
      if (gen != _gen) return;
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

  /// Stage every file of the unstaged side, or unstage every staged one.
  Future<String?> moveAll({required bool staged}) {
    final files = staged ? this.staged : unstaged;
    return act((b) async {
      for (final f in files) {
        staged ? await b.unstage(f.path) : await b.stage(f.path);
      }
    });
  }

  /// Stage an unstaged file, or unstage a staged one.
  Future<String?> moveFile(String path, {required bool staged}) =>
      act((b) => staged ? b.unstage(path) : b.stage(path));

  Future<String?> discardFile(String path) => act((b) => b.discard(path));

  /// Stage a hunk of the selected unstaged file, or unstage one of the selected staged file.
  Future<String?> moveHunk(Hunk h) {
    final path = selected!;
    return act((b) => selectedStaged ? b.unstageHunk(path, h) : b.stageHunk(path, h));
  }

  Future<String?> discardHunk(Hunk h) {
    final path = selected!;
    return act((b) => b.discardHunk(path, h));
  }

  /// Open the selected file in Neovim at [line] (new side only; deletions have no line there).
  Future<String?> openLine(int line, {required bool isOld}) async {
    final path = selected;
    if (isOld || path == null) return null;
    return session.run((b) => b.open(path, line));
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    session.gitChanged.removeListener(refresh);
    super.dispose();
  }
}

/// What a status row shows for [f] on its side: conflicted, untracked, added, deleted, renamed or
/// modified.
String fileKind(StatusFile f, {required bool staged}) {
  if (f.conflicted) return 'conflicted';
  if (f.untracked) return 'untracked';
  return switch (staged ? f.index : f.worktree) {
    'A' => 'added',
    'D' => 'deleted',
    'R' => 'renamed',
    _ => 'modified',
  };
}
