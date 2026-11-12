import 'package:flutter/widgets.dart';

import '../backend/models.dart';
import '../timing/ui_timing.dart';
import 'list_pair.dart';
import 'session.dart';

export 'list_pair.dart' show dirOf;

/// Unified or side-by-side diff.
enum DiffLayout { unified, sideBySide }

/// The part of the Pull request view the list keys (j/k, gg/G, Enter) act on; Tab cycles them.
enum PrPane { files, commits, diff }

/// State of the Pull request view: two revisions, their commits and the base...head diff, or one
/// commit's diff when narrowed to it.
class PrState extends ChangeNotifier {
  PrState(this.session) {
    session.gitChanged.addListener(refresh);
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

  // View choices, for this session only.
  DiffLayout layout = DiffLayout.unified;
  bool wrap = true;
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

  /// j/k, gg/G, Ctrl+D/U: move in the active pane.
  void moveCursor(int delta) {
    switch (pane) {
      case PrPane.files:
        selectNext(delta);
      case PrPane.commits:
        if (commits.isEmpty) return;
        commitCursor = (commitCursor + delta).clamp(0, commits.length - 1);
        notifyListeners();
      case PrPane.diff:
        moveHunk(delta);
    }
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

  /// h / l: fold or unfold the selected file's folder.
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

  void toggleLayout() {
    layout = layout == DiffLayout.unified ? DiffLayout.sideBySide : DiffLayout.unified;
    notifyListeners();
  }

  void setLayout(DiffLayout l) {
    layout = l;
    notifyListeners();
  }

  void toggleWrap() {
    wrap = !wrap;
    notifyListeners();
  }

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
    baseFocus.dispose();
    headFocus.dispose();
    super.dispose();
  }
}

/// Paths in the order the file tree shows them: folders sorted, files sorted inside them.
List<String> treeOrder(Iterable<String> paths) {
  final list = paths.toList()
    ..sort((a, b) {
      final d = dirOf(a).compareTo(dirOf(b));
      return d != 0 ? d : a.compareTo(b);
    });
  return list;
}
