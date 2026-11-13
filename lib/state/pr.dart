import 'package:flutter/widgets.dart';

import '../backend/models.dart';
import '../timing/ui_timing.dart';
import 'list_pair.dart';
import 'session.dart';

export 'diff_prefs.dart' show DiffLayout;
export 'list_pair.dart' show dirOf, compareTreeOrder;

/// The part of the Pull request view the list keys (j/k, gg/G, Enter) act on; Tab cycles them.
enum PrPane { files, commits, diff }

/// State of the Pull request view: two revisions, their commits and the base...head diff, or one
/// commit's diff when narrowed to it.
class PrState extends ChangeNotifier {
  PrState(this.session) {
    session.gitChanged.addListener(refresh);
    session.diffPrefs.addListener(notifyListeners);
    refresh();
  }

  final Session session;
  Branches? branches;
  String? base, head;
  List<Commit> commits = [];
  PrDiff? diff;
  String? selected; // path of the selected file
  bool loading = false;
  String? error;

  /// The commit the file tree and diff are narrowed to; null: the full base..head range.
  Commit? narrowed;

  // View choices, for this session only (layout and wrap are shared with Changes).
  DiffLayout get layout => session.diffPrefs.layout;
  bool get wrap => session.diffPrefs.wrap;

  /// FILES CHANGED (0) over COMMITS (1); files have the room at start.
  final lists = ListPair();
  Set<String> collapsedDirs = {};

  /// Where the keys act: the active pane, the commit under the cursor, the current hunk of the
  /// selected file (-1: none yet).
  PrPane pane = PrPane.files;
  int commitCursor = 0;
  int hunk = -1;

  /// The revision pickers' focus, so keys can jump to them.
  final baseFocus = FocusNode(debugLabel: 'base picker');
  final headFocus = FocusNode(debugLabel: 'head picker');

  int _gen = 0;
  String? _root;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  DiffFile? get selectedFile => diff?.files.where((f) => f.path == selected).firstOrNull;
  List<String> get branchNames => branches?.list.map((x) => x.name).toList() ?? [];

  /// Reload branches, then commits and diff for the picked pair (keeps the selection).
  /// [base] and [head] may be any revision git accepts; only unknown branch names are replaced.
  Future<void> refresh() => UiTiming.instance.time('pr.refresh', _refresh);

  Future<void> _refresh() async {
    final b = session.backend;
    if (b == null) return;
    final gen = ++_gen;
    // Another repo (the Active Directory moved): start over with its default branches.
    final root = session.repo?.root;
    if (root != _root) {
      _root = root;
      base = head = selected = null;
      narrowed = null;
      collapsedDirs = {};
    }
    loading = true;
    notifyListeners();
    try {
      final br = await b.branches();
      if (gen != _gen) return;
      branches = br;
      final names = br.list.map((x) => x.name).toList();
      // Base: the checked-out branch; main or master only when HEAD is detached.
      if (base == null || base!.isEmpty) {
        final cur = br.current;
        base = cur != null && names.contains(cur)
            ? cur
            : (names.contains('main') ? 'main' : (names.contains('master') ? 'master' : cur));
      }
      if (head == null || head!.isEmpty) {
        final others = br.list.where((x) => x.name != base).toList()..sort((a, b) => b.date.compareTo(a.date));
        head = others.isNotEmpty ? others.first.name : base;
      }
      if (base != null && head != null && base != head) {
        final n = narrowed;
        final results = await Future.wait([
          b.log(base!, head!),
          n == null ? b.diff(base!, head!) : b.diff('${n.sha}~1', n.sha),
        ]);
        if (gen != _gen) return;
        commits = results[0] as List<Commit>;
        diff = results[1] as PrDiff;
        if (n != null && !commits.any((c) => c.sha == n.sha)) {
          narrowed = null;
          diff = await b.diff(base!, head!);
          if (gen != _gen) return;
        }
      } else {
        commits = [];
        diff = null;
        narrowed = null;
      }
      if (selected == null || selectedFile == null) {
        selected = diff?.files.firstOrNull?.path;
      }
      error = null;
    } catch (e) {
      if (gen != _gen) return;
      error = '$e';
    } finally {
      if (gen == _gen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void pick({String? base, String? head}) {
    if (base != null) this.base = base.trim();
    if (head != null) this.head = head.trim();
    selected = null;
    narrowed = null;
    refresh();
  }

  void swap() => pick(base: head, head: base);

  /// Whether there is something to merge: both sides are picked and they differ.
  bool get canMerge => base != null && head != null && base != head && (diff?.files.isNotEmpty ?? false);

  /// Merge head into base (the backend checks base out when it is not the current branch).
  /// Returns the error text, or null.
  Future<String?> merge() async {
    final (b, h) = (base, head);
    if (b == null || h == null) return 'pick a base and a head first';
    final err = await session.run((x) async => await x.merge(b, h));
    await refresh();
    return err;
  }

  void pickBase(String rev) => pick(base: rev);
  void pickHead(String rev) => pick(head: rev);
  void showAllCommits() => narrow(null);
  void makeFilesDominant() => _lists(() => lists.toggleDominant(0));
  void makeCommitsDominant() => _lists(() => lists.toggleDominant(1));
  void toggleFiles() => _lists(() => lists.toggleCollapsed(0));
  void toggleCommits() => _lists(() => lists.toggleCollapsed(1));
  bool get filesCollapsed => lists.collapsed[0];
  bool get commitsCollapsed => lists.collapsed[1];

  void _lists(void Function() change) {
    change();
    if (!_panes.contains(pane)) pane = PrPane.diff;
    notifyListeners();
  }

  void select(String path) {
    if (path != selected) hunk = -1;
    selected = path;
    _expandTo(path);
    notifyListeners();
  }

  /// A click in [p] (a file, a commit, the diff): that pane is the active one, as it is after a key
  /// that goes there. Not for a folded or empty pane.
  void clickPane(PrPane p) {
    if (!_panes.contains(p) || pane == p) return;
    pane = p;
    notifyListeners();
  }

  /// A click on commit [i]: the commits pane is active, the cursor is on it, and the diff narrows to it.
  void clickCommit(int i) {
    commitCursor = i;
    pane = PrPane.commits;
    narrow(commits[i]);
  }

  // Keys -------------------------------------------------------------------------------------------

  List<PrPane> get _panes => [
    if (!filesCollapsed) PrPane.files,
    if (!commitsCollapsed && commits.isNotEmpty) PrPane.commits,
    PrPane.diff,
  ];

  /// Tab / Shift+Tab: the base picker, the head picker, then the panes. Returns the picker to
  /// focus, or null when a pane takes the keys.
  FocusNode? nextPane(int delta) {
    final panes = _panes;
    final i = panes.indexOf(pane);
    final at = baseFocus.hasFocus ? 0 : (headFocus.hasFocus ? 1 : 2 + (i < 0 ? 0 : i));
    final to = (at + delta) % (panes.length + 2);
    if (to < 2) return to == 0 ? baseFocus : headFocus;
    pane = panes[to - 2];
    notifyListeners();
    return null;
  }

  /// The diff's scroll position: Up / Down in the diff pane scroll it, DiffScroll.step lines per press.
  final diffScroll = DiffScroll();

  /// The list pane the diff was entered from, for Left.
  PrPane _lastList = PrPane.files;

  /// Right: from a list to the diff. Left: from the diff back to the list it came from.
  void movePane(int delta) {
    final ps = _panes;
    if (pane != PrPane.diff) _lastList = pane;
    if (delta > 0) {
      pane = PrPane.diff;
    } else if (pane == PrPane.diff) {
      pane = ps.contains(_lastList) ? _lastList : ps.first;
    }
    notifyListeners();
  }

  /// j/k, arrows, gg/G, Ctrl+D/U: move in the active pane (the diff scrolls by lines).
  /// [big] (Shift): the diff scrolls [DiffScroll.bigStep] lines instead of [DiffScroll.step].
  /// One step past the end of a list goes to the pane visually next to it: past the last file to
  /// COMMITS, past the first commit to FILES, past the first file to the head picker, which is
  /// returned for the caller to focus.
  FocusNode? moveCursor(int delta, {bool big = false}) {
    switch (pane) {
      case PrPane.files:
        final files = treeOrder(diff?.files.map((f) => f.path) ?? const []);
        if (delta == 1 && files.isNotEmpty && selected == files.last) return _enter(PrPane.commits);
        if (delta == -1 && files.isNotEmpty && selected == files.first) return headFocus;
        selectNext(delta);
      case PrPane.commits:
        if (commits.isEmpty) return null;
        if (delta == -1 && commitCursor == 0) return _enter(PrPane.files);
        commitCursor = (commitCursor + delta).clamp(0, commits.length - 1);
        notifyListeners();
      case PrPane.diff:
        diffScroll.byLines(delta * (big ? DiffScroll.bigStep : DiffScroll.step));
    }
    return null;
  }

  /// Tab / Shift+Tab leave the cycle of the Pull request stops (base, head, panes) in [delta]'s
  /// direction: the mode rail is the stop before the first and after the last.
  bool leavesCycle(int delta) {
    final panes = _panes;
    final i = panes.indexOf(pane);
    final at = baseFocus.hasFocus ? 0 : (headFocus.hasFocus ? 1 : 2 + (i < 0 ? 0 : i));
    final to = at + delta;
    return to < 0 || to >= panes.length + 2;
  }

  /// The last stop of the cycle (the diff), for Shift+Tab from the rail.
  void goLastPane() {
    pane = _panes.last;
    notifyListeners();
  }

  /// Ctrl+Up / Ctrl+Down: the pane visually above or below, counting the two pickers (base, head,
  /// FILES CHANGED, COMMITS). Returns what gets the keyboard: a picker, or [shell] for a pane.
  /// Nothing is above the base picker or below the commits (the focus stays); the diff is alone in
  /// its column.
  FocusNode vertical(int dir, FocusNode shell) {
    final lists = _panes.where((p) => p != PrPane.diff).toList();
    final stay = baseFocus.hasFocus ? baseFocus : (headFocus.hasFocus ? headFocus : shell);
    final inPicker = baseFocus.hasFocus || headFocus.hasFocus;
    if (pane == PrPane.diff && !inPicker) return stay;
    final at = baseFocus.hasFocus ? 0 : (headFocus.hasFocus ? 1 : 2 + lists.indexOf(pane));
    final to = at + dir;
    if (to < 0 || to >= lists.length + 2) return stay;
    if (to < 2) return to == 0 ? baseFocus : headFocus;
    final target = lists[to - 2];
    if (target == PrPane.files && dir < 0) {
      _enter(PrPane.files); // coming up from COMMITS: the lowest visible file
    } else {
      pane = target;
      notifyListeners();
    }
    return shell;
  }

  /// Shift+[ and Shift+]: three items up or down in the active list; in the diff, a normal scroll.
  /// They stay inside the list (no hop to the neighbouring pane).
  void jump(int dir) => moveCursor(pane == PrPane.diff ? dir : dir * listJump);

  /// Items one Shift+[ / Shift+] moves in a list.
  static const listJump = 3;

  /// Bumps when the keyboard comes up into FILES CHANGED from COMMITS: the file tree selects the
  /// lowest visible file then.
  final selectBottomOfFiles = ValueNotifier<int>(0);

  /// Make [p] the active pane when it can be reached (it is not folded or empty).
  FocusNode? _enter(PrPane p) {
    if (_panes.contains(p)) {
      pane = p;
      if (p == PrPane.files) selectBottomOfFiles.value++;
      notifyListeners();
    }
    return null;
  }

  /// ]c / [c: the next or previous hunk of the selected file.
  void moveHunk(int delta) {
    final n = selectedFile?.hunks.length ?? 0;
    if (n == 0) return;
    hunk = hunk < 0 ? (delta > 0 ? 0 : n - 1) : (hunk + delta).clamp(0, n - 1);
    notifyListeners();
  }

  /// Enter: on a commit, narrow to it; on a file, go to its diff.
  void enter() {
    if (pane == PrPane.commits && commits.isNotEmpty) return narrow(commits[commitCursor.clamp(0, commits.length - 1)]);
    if (pane == PrPane.files) {
      pane = PrPane.diff;
      notifyListeners();
    }
  }

  /// zc / zo: fold or unfold the selected file's folder.
  void foldSelected({required bool fold}) {
    final d = dirOf(selected ?? '');
    if (d.isEmpty) return;
    fold ? collapsedDirs.add(d) : collapsedDirs.remove(d);
    notifyListeners();
  }

  /// Show a diff line in Neovim: the working tree file when head is checked out and the view
  /// shows the full range, else a read-only copy at the revision (deleted lines: the old one).
  /// Returns the error text, or null.
  Future<String?> openInNeovim(int line, {required bool isOld}) {
    final f = selectedFile;
    if (f == null || head == null) return Future.value(null);
    final n = narrowed;
    final rev = isOld ? (n == null ? diff!.mergeBase : '${n.sha}~1') : (n?.sha ?? head!);
    final path = isOld ? f.oldPath : f.path;
    final live = !isOld && n == null && session.repo?.head == head;
    return session.run((b) => live ? b.open(path, line) : b.show(rev, path, line));
  }

  /// o: the current hunk's first changed line (or the file's first hunk) in Neovim.
  Future<String?> openCurrent() {
    final hunks = selectedFile?.hunks ?? const <Hunk>[];
    if (hunks.isEmpty) return openInNeovim(1, isOld: false);
    return openInNeovim(hunks[hunk < 0 ? 0 : hunk].firstChangedLine, isOld: false);
  }

  /// Show only [c]'s changes; the same commit again (or null) returns to the full range.
  void narrow(Commit? c) {
    narrowed = c == null || c.sha == narrowed?.sha ? null : c;
    hunk = -1;
    selected = null;
    refresh();
  }

  /// Next / previous file in tree order (folders sorted, files sorted inside them).
  void selectNext(int delta) {
    final files = treeOrder(diff?.files.map((f) => f.path) ?? const []);
    if (files.isEmpty) return;
    final i = files.indexOf(selected ?? '');
    select(files[(i < 0 ? 0 : i + delta).clamp(0, files.length - 1)]);
  }

  void toggleLayout() => session.diffPrefs.toggleLayout();

  void setLayout(DiffLayout l) => session.diffPrefs.setLayout(l);

  void toggleWrap() => session.diffPrefs.toggleWrap();

  void toggleDir(String dir) {
    collapsedDirs.contains(dir) ? collapsedDirs.remove(dir) : collapsedDirs.add(dir);
    notifyListeners();
  }

  /// Collapse every folder except the selected file's; or, when any is collapsed, expand all.
  void toggleAllDirs() {
    if (collapsedDirs.isNotEmpty) {
      collapsedDirs = {};
    } else {
      collapsedDirs = foldAll(diff?.files.map((f) => f.path) ?? const [], keep: selected);
    }
    notifyListeners();
  }

  void expandAllDirs() {
    if (collapsedDirs.isNotEmpty) toggleAllDirs();
  }

  void collapseAllDirs() {
    if (collapsedDirs.isEmpty) toggleAllDirs();
  }

  void _expandTo(String path) => collapsedDirs.remove(dirOf(path));

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    session.gitChanged.removeListener(refresh);
    session.diffPrefs.removeListener(notifyListeners);
    baseFocus.dispose();
    headFocus.dispose();
    diffScroll.dispose();
    selectBottomOfFiles.dispose();
    super.dispose();
  }
}

/// Paths in the order the file tree shows them: folders sorted, files sorted inside them.
List<String> treeOrder(Iterable<String> paths) {
  return paths.toList()..sort(compareTreeOrder);
}
