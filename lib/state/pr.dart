import 'package:flutter/widgets.dart';

import '../backend/models.dart';
import 'session.dart';

/// Unified or side-by-side diff.
enum DiffLayout { unified, sideBySide }

/// Which left-pane list takes the free height in the Pull request view.
enum Dominant { files, commits }

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
  Dominant dominant = Dominant.files;
  bool commitsCollapsed = false;
  Set<String> collapsedDirs = {};

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
  Future<void> refresh() async {
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
      if (base == null || base!.isEmpty) {
        base = names.contains('main') ? 'main' : (names.contains('master') ? 'master' : br.current);
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
  void makeFilesDominant() => toggleDominant(Dominant.files);
  void makeCommitsDominant() => toggleDominant(Dominant.commits);

  void select(String path) {
    selected = path;
    _expandTo(path);
    notifyListeners();
  }

  /// Show only [c]'s changes; the same commit again (or null) returns to the full range.
  void narrow(Commit? c) {
    narrowed = c == null || c.sha == narrowed?.sha ? null : c;
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

  void toggleDominant(Dominant d) {
    dominant = dominant == d ? (d == Dominant.files ? Dominant.commits : Dominant.files) : d;
    if (dominant == Dominant.commits) commitsCollapsed = false;
    notifyListeners();
  }

  void toggleCommits() {
    commitsCollapsed = !commitsCollapsed;
    if (commitsCollapsed && dominant == Dominant.commits) dominant = Dominant.files;
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
      // Top-level files have no folder row, so '' never folds.
      collapsedDirs = {for (final f in diff?.files ?? <DiffFile>[]) dirOf(f.path)}
        ..remove('')
        ..remove(dirOf(selected ?? ''));
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

String dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
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
