import 'dart:async';

import 'package:flutter/widgets.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import '../timing/ui_timing.dart';
import 'list_pair.dart';
import 'session.dart';

/// The panes of the Changes view, in visual order: STAGED, CHANGES, the diff (the commit message
/// is a text field between CHANGES and the diff; Tab visits it too).
enum ChangesPane { staged, unstaged, diff }

/// State of the Changes view: working tree vs HEAD, the selected file's diff, and actions.
class ChangesState extends ChangeNotifier {
  ChangesState(this.session) {
    session.gitChanged.addListener(refresh);
    session.diffPrefs.addListener(notifyListeners);
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

  DiffLayout get layout => session.diffPrefs.layout;
  bool get wrap => session.diffPrefs.wrap;

  void toggleLayout() => session.diffPrefs.toggleLayout();
  void toggleWrap() => session.diffPrefs.toggleWrap();
  bool get hunkHeaders => session.diffPrefs.hunkHeaders;
  void toggleHunkHeaders() => session.diffPrefs.toggleHunkHeaders();

  /// STAGED (0) over CHANGES (1), as in the Pull request view; CHANGES have the room at start.
  final lists = ListPair(dominant: 1);

  /// The folded folders of each list.
  final collapsedDirs = [<String>{}, <String>{}];

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// The local branches, for the branch switcher.
  Branches? branches;
  List<String> get branchNames => branches?.list.map((x) => x.name).toList() ?? [];

  /// The files a checkout would overwrite: those with uncommitted changes to tracked files
  /// (untracked files stay).
  List<StatusFile> get wipedByCheckout => [
    for (final f in status?.files ?? const <StatusFile>[])
      if (!f.untracked) f,
  ]..sort((a, b) => compareTreeOrder(a.path, b.path));

  /// Both lists are in the order the tree shows them, so the keys walk the rows top to bottom.
  List<StatusFile> get staged => _inTreeOrder(status?.files.where((f) => f.staged));
  List<StatusFile> get unstaged => _inTreeOrder(status?.files.where((f) => f.unstaged || f.untracked || f.conflicted));

  static List<StatusFile> _inTreeOrder(Iterable<StatusFile>? files) =>
      (files?.toList() ?? [])..sort((a, b) => compareTreeOrder(a.path, b.path));

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
      final (st, br) = await (b.status(), b.branches()).wait;
      if (gen != _gen || _pending > 0) return;
      status = st;
      branches = br;
      _handOverRoom();
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
    _loadDiffSoon();
  }

  /// How long the selection must rest before its diff is fetched: holding an arrow key walks
  /// through many files, and only the one it stops on needs a request.
  static const diffDelay = Duration(milliseconds: 120);

  Timer? _diffTimer;
  int _diffGen = 0;

  void _loadDiffSoon() {
    _diffTimer?.cancel();
    _diffTimer = Timer(diffDelay, () => UiTiming.instance.time('changes.diff', _loadDiff));
  }

  /// Fetches the diff of the selected file only (not the status again); a result for a file that is
  /// no longer selected is dropped.
  Future<void> _loadDiff() async {
    final b = session.backend, path = selected;
    if (b == null || path == null || _disposed) return;
    final staged = selectedStaged, gen = ++_diffGen;
    try {
      final d = await b.diffFile(path, staged: staged);
      if (gen != _diffGen || _disposed) return;
      diff = d;
      error = null;
    } catch (e) {
      if (gen != _diffGen || _disposed) return;
      error = '$e';
    }
    notifyListeners();
  }

  /// Files in list order: staged first, then the rest, each with its side.
  List<(String, bool)> get _order => [for (final f in staged) (f.path, true), for (final f in unstaged) (f.path, false)];

  /// The part of the Changes view the up / down keys act on; Left / Right and Tab switch.
  ChangesPane _pane = ChangesPane.staged;

  /// The active pane; one that has no files (or is folded) hands over to the first reachable one.
  ChangesPane get pane => panes.contains(_pane) ? _pane : panes.first;

  /// The panes the keys can reach, in visual order: empty and folded lists are left out.
  List<ChangesPane> get panes => [
    if (staged.isNotEmpty && !lists.collapsed[0]) ChangesPane.staged,
    if (unstaged.isNotEmpty && !lists.collapsed[1]) ChangesPane.unstaged,
    ChangesPane.diff,
  ];

  /// The diff's scroll position: Up / Down in the diff pane scroll it, DiffScroll.step lines per press.
  final diffScroll = DiffScroll();

  /// Per list (STAGED, CHANGES): bumps when the keyboard comes up into it from below; its file
  /// tree selects the lowest visible file then.
  final selectBottom = [ValueNotifier<int>(0), ValueNotifier<int>(0)];

  /// The list pane the diff was entered from, for Left.
  ChangesPane _lastList = ChangesPane.staged;

  /// Right: from a list to the diff. Left: from the diff back to the list it came from.
  void movePane(int delta) {
    final ps = panes;
    if (pane != ChangesPane.diff) _lastList = pane;
    if (delta > 0) return goTo(ChangesPane.diff);
    if (pane == ChangesPane.diff) goTo(ps.contains(_lastList) ? _lastList : ps.first);
  }

  /// Tab / Shift+Tab leave the cycle (STAGED, CHANGES, commit message, diff) in [delta]'s
  /// direction: the mode rail is the stop before the first and after the last.
  bool tabLeaves({required bool fromMessage, required int delta}) {
    final slots = [...panes.where((p) => p != ChangesPane.diff), null, ChangesPane.diff];
    final at = fromMessage ? slots.indexOf(null) : slots.indexOf(pane);
    final to = at + delta;
    return to < 0 || to >= slots.length;
  }

  /// Ctrl+Up / Ctrl+Down: the pane visually above or below (STAGED, CHANGES, commit message).
  /// Returns true when the commit message should get the keyboard. The diff is alone in its column.
  bool vertical({required int dir, required bool fromMessage}) {
    final lists = panes.where((p) => p != ChangesPane.diff).toList();
    if (!fromMessage && !lists.contains(pane)) return false;
    final at = fromMessage ? lists.length : lists.indexOf(pane);
    final to = at + dir;
    if (to < 0 || to > lists.length) return fromMessage;
    if (to == lists.length) return true;
    goTo(lists[to]);
    if (dir < 0) selectBottom[lists[to] == ChangesPane.staged ? 0 : 1].value++;
    return false;
  }

  /// Tab / Shift+Tab: the pane after (before) [pane] in the cycle of [panes] plus the commit
  /// message; null when the message is next. [fromMessage]: the message has the keyboard.
  ChangesPane? tabFrom({required bool fromMessage, required int delta}) {
    final ps = panes;
    final slots = [...ps.where((p) => p != ChangesPane.diff), null, ChangesPane.diff]; // null: message
    final at = fromMessage ? slots.indexOf(null) : slots.indexOf(pane);
    final to = slots[(at + delta) % slots.length];
    if (to != null) goTo(to);
    if (to != null && to != ChangesPane.diff && fromMessage && delta < 0) {
      selectBottom[to == ChangesPane.staged ? 0 : 1].value++; // up from the message: the lowest visible
    }
    return to;
  }

  /// Make [p] the active pane; a list pane selects its first (with [last]: last) file unless one of
  /// its files is selected ([force]: select it anyway).
  void goTo(ChangesPane p, {bool last = false, bool force = false}) {
    _pane = p;
    final side = switch (p) {
      ChangesPane.staged => true,
      ChangesPane.unstaged => false,
      ChangesPane.diff => null,
    };
    final files = side == null ? const <StatusFile>[] : (side ? staged : unstaged);
    final inside = selectedStaged == side && files.any((f) => f.path == selected);
    if (side != null && files.isNotEmpty && (force || !inside)) {
      select((last ? files.last : files.first).path, staged: side);
      return;
    }
    notifyListeners();
  }

  /// A click on a file row: select it and make its list the active pane.
  void pick(String path, {required bool staged}) {
    _pane = staged ? ChangesPane.staged : ChangesPane.unstaged;
    select(path, staged: staged);
  }

  /// j / k, arrows: the next or previous file within the active list; in the diff, scroll lines
  /// ([big] (Shift): [DiffScroll.bigStep] of them instead of [DiffScroll.step]). One step past the
  /// end of a list goes to the pane visually next to it: past the last staged file to CHANGES, past
  /// the first changed file to STAGED, past the last file of the last list to the commit message
  /// (then true is returned: the caller gives it the keyboard).
  bool moveCursor(int delta, {bool big = false}) {
    if (pane == ChangesPane.diff) {
      diffScroll.byLines(delta * (big ? DiffScroll.bigStep : DiffScroll.step));
      return false;
    }
    final side = pane == ChangesPane.staged;
    final files = side ? staged : unstaged;
    if (files.isEmpty) return false;
    final i = selectedStaged == side ? files.indexWhere((f) => f.path == selected) : -1;
    final ps = panes;
    if (delta == 1 && i == files.length - 1) {
      if (side && ps.contains(ChangesPane.unstaged)) goTo(ChangesPane.unstaged, last: false, force: true);
      return !side || !ps.contains(ChangesPane.unstaged);
    }
    if (delta == -1 && i == 0) {
      if (!side && ps.contains(ChangesPane.staged)) {
        goTo(ChangesPane.staged, last: true, force: true); // without a tree on screen: the last file
        selectBottom[0].value++;
      }
      return false;
    }
    final next = files[(i < 0 ? 0 : i + delta).clamp(0, files.length - 1)];
    if (next.path != selected || side != selectedStaged) select(next.path, staged: side);
    return false;
  }

  /// The mouse wheel stepping over a list: the next or previous file of the list on side [staged],
  /// which becomes the active pane. Stays inside the list (no hop to the neighbouring one).
  void stepFile(int delta, {required bool staged}) {
    final files = staged ? this.staged : unstaged;
    if (files.isEmpty) return;
    final i = selectedStaged == staged ? files.indexWhere((f) => f.path == selected) : -1;
    final next = files[(i < 0 ? 0 : i + delta).clamp(0, files.length - 1)];
    _pane = staged ? ChangesPane.staged : ChangesPane.unstaged;
    if (next.path != selected || staged != selectedStaged) {
      select(next.path, staged: staged);
    } else {
      notifyListeners();
    }
  }

  /// Shift+[ and Shift+]: three files up or down in the active list; in the diff, a normal scroll.
  void jump(int dir) {
    if (pane == ChangesPane.diff) {
      moveCursor(dir);
    } else {
      moveCursor(dir * 3);
    }
  }

  /// gg / G: the first or last file in list order; also the next or previous one.
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
  Future<String?> moveAll({required bool staged}) => _moveSet(staged ? this.staged : unstaged, staged: staged, name: 'All');

  /// Stage (or unstage) the files that sit directly in [dir] of the unstaged (staged) side: the
  /// files the tree shows under that folder row.
  Future<String?> moveDir(String dir, {required bool staged}) {
    final files = [
      for (final f in staged ? this.staged : unstaged)
        if (f.path.substring(0, f.path.lastIndexOf('/') + 1) == '$dir/') f,
    ];
    return _moveSet(files, staged: staged, name: 'Dir');
  }

  Future<String?> _moveSet(Iterable<StatusFile> files, {required bool staged, required String name}) {
    final paths = {for (final f in files) f.path};
    return act(
      staged ? 'unstage$name' : 'stage$name',
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
    _handOverRoom();
  }

  /// STAGED has nothing to show: the room it had ("most room") goes to CHANGES, which unfolds.
  void _handOverRoom() {
    if (staged.isNotEmpty || lists.dominant != 0) return;
    lists.dominant = 1;
    lists.collapsed[1] = false;
  }

  /// Switch to [branch]; [how] says what to do with uncommitted changes (null: git refuses when
  /// they are in the way). Returns the error text, or null.
  Future<String?> switchBranch(String branch, {CheckoutHow? how}) => act(
    'checkout',
    (b) => b.checkout(branch, how: how),
  );

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
    _diffGen++;
    _diffTimer?.cancel();
    session.gitChanged.removeListener(refresh);
    session.diffPrefs.removeListener(notifyListeners);
    diffScroll.dispose();
    for (final n in selectBottom) {
      n.dispose();
    }
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
