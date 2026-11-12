import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import '../timing/ui_timing.dart';
import 'list_pair.dart';
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

  /// The current hunk of the selected file (]c / [c); -1: none, keys act on the whole file.
  int hunk = -1;
  int _gen = 0;

  /// Actions still waiting for git. A refresh doesn't show a status while one runs: it could
  /// predate the action and flip an optimistic move back; the action's own refresh follows.
  int _pending = 0;
  bool _disposed = false;

  /// STAGED (0) over CHANGES (1), as in the Pull request view; CHANGES have the room at start.
  final lists = ListPair(dominant: 1);

  /// The folded folders of each list.
  final collapsedDirs = [<String>{}, <String>{}];

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<StatusFile> get staged => status?.files.where((f) => f.staged).toList() ?? [];
  List<StatusFile> get unstaged => status?.files.where((f) => f.unstaged || f.untracked || f.conflicted).toList() ?? [];

  List<StatusFile> files(int list) => list == 0 ? staged : unstaged;

  // Lists ----------------------------------------------------------------------------------------

  void toggleList(int i) => _lists(() => lists.toggleCollapsed(i));
  void makeDominant(int i) => _lists(() => lists.toggleDominant(i));
  void toggleDir(int list, String dir) => _lists(() {
    final c = collapsedDirs[list];
    c.contains(dir) ? c.remove(dir) : c.add(dir);
  });

  /// The header button: collapse every folder but the selected file's; when any is folded, expand all.
  void toggleAllDirs(int list) => _lists(() {
    final c = collapsedDirs[list];
    final folded = c.isNotEmpty;
    c.clear();
    if (!folded) c.addAll(foldAll(files(list).map((f) => f.path), keep: selected));
  });

  /// zR / zM: every folder of both lists.
  void expandAllDirs() => _lists(() {
    for (final c in collapsedDirs) {
      c.clear();
    }
  });
  void collapseAllDirs() => _lists(() {
    for (final i in [0, 1]) {
      collapsedDirs[i]
        ..clear()
        ..addAll(foldAll(files(i).map((f) => f.path), keep: selected));
    }
  });

  void _lists(void Function() change) {
    change();
    notifyListeners();
  }

  Future<void> refresh() => UiTiming.instance.time('changes.refresh', _refresh);

  Future<void> _refresh() async {
    final b = session.backend;
    if (b == null || _pending > 0) return;
    final gen = ++_gen;
    try {
      final st = await b.status();
      if (gen != _gen || _pending > 0) return;
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
    if (path != selected || staged != selectedStaged) hunk = -1;
    selected = path;
    selectedStaged = staged;
    collapsedDirs[staged ? 0 : 1].remove(dirOf(path));
    diff = null;
    notifyListeners();
    refresh();
  }

  /// Files in list order: staged first, then the rest, each with its side.
  List<(String, bool)> get _order => [for (final f in staged) (f.path, true), for (final f in unstaged) (f.path, false)];

  /// j / k, gg / G: the next or previous file in list order.
  void moveSelection(int delta) {
    final order = _order;
    if (order.isEmpty) return;
    final i = order.indexWhere((e) => e.$1 == selected && e.$2 == selectedStaged);
    final next = order[(i < 0 ? 0 : i + delta).clamp(0, order.length - 1)];
    if (next.$1 != selected || next.$2 != selectedStaged) select(next.$1, staged: next.$2);
  }

  /// ]c / [c: the next or previous hunk of the selected file.
  void moveHunk(int delta) {
    final n = diff?.hunks.length ?? 0;
    if (n == 0) return;
    hunk = hunk < 0 ? (delta > 0 ? 0 : n - 1) : (hunk + delta).clamp(0, n - 1);
    notifyListeners();
  }

  Hunk? get currentHunk {
    final hs = diff?.hunks ?? const <Hunk>[];
    return hunk >= 0 && hunk < hs.length ? hs[hunk] : null;
  }

  /// `-`: stage or unstage the current hunk, or the whole file when no hunk is current.
  Future<String?> toggleCurrent() {
    final h = currentHunk, path = selected;
    if (path == null) return Future.value(null);
    return h != null ? toggleHunk(h) : moveFile(path, staged: selectedStaged);
  }

  /// `s` / `u`: only when the selection is on the side it moves from.
  Future<String?> stageCurrent() => selectedStaged ? Future.value(null) : toggleCurrent();
  Future<String?> unstageCurrent() => selectedStaged ? toggleCurrent() : Future.value(null);

  /// The line `o` opens: the current hunk's first changed line, else the first hunk's, else 1.
  int get currentLine => (currentHunk ?? diff?.hunks.firstOrNull)?.firstChangedLine ?? 1;

  /// Run an action, then refresh; timed as `changes.<name>`. [optimistic] changes what the view
  /// shows before git answers; the refresh after the action keeps it or puts it back. Returns the
  /// error text, or null.
  Future<String?> act(String name, Future<void> Function(Backend b) action, {void Function()? optimistic}) async {
    final span = UiTiming.instance.span('changes.$name');
    busy = true;
    _pending++;
    optimistic?.call();
    notifyListeners();
    if (optimistic != null) span.markPainted();
    final err = await session.run(action);
    span.mark('git');
    _pending--;
    busy = false;
    await refresh();
    span.end();
    return err;
  }

  Future<String?> commit(String message) => act('commit', (b) => b.commit(message));

  /// Stage every file of the unstaged side, or unstage every staged one.
  Future<String?> moveAll({required bool staged}) {
    final paths = {for (final f in staged ? this.staged : unstaged) f.path};
    return act(
      staged ? 'unstageAll' : 'stageAll',
      (b) async {
        for (final p in paths) {
          staged ? await b.unstage(p) : await b.stage(p);
        }
      },
      optimistic: () => _moveLocally(paths, toStaged: !staged),
    );
  }

  /// Stage an unstaged file, or unstage a staged one. The file moves to the other list at once.
  Future<String?> moveFile(String path, {required bool staged}) => act(
    staged ? 'unstage' : 'stage',
    (b) => staged ? b.unstage(path) : b.stage(path),
    optimistic: () => _moveLocally({path}, toStaged: !staged),
  );

  /// What git status will most likely say after staging or unstaging [paths] as whole files; the
  /// selection follows its file.
  void _moveLocally(Set<String> paths, {required bool toStaged}) {
    final st = status;
    if (st == null) return;
    status = st.withFiles([for (final f in st.files) paths.contains(f.path) ? f.moved(toStaged: toStaged) : f]);
    if (selected != null && paths.contains(selected)) selectedStaged = toStaged;
  }

  Future<String?> discardFile(String path) => act('discard', (b) => b.discard(path));

  /// Stage a hunk of the selected unstaged file, or unstage one of the selected staged file. Not
  /// optimistic: the other hunks' line numbers shift, only git knows them.
  Future<String?> toggleHunk(Hunk h) {
    final path = selected!;
    return act(
      selectedStaged ? 'unstageHunk' : 'stageHunk',
      (b) => selectedStaged ? b.unstageHunk(path, h) : b.stageHunk(path, h),
    );
  }

  Future<String?> discardHunk(Hunk h) {
    final path = selected!;
    return act('discardHunk', (b) => b.discardHunk(path, h));
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
