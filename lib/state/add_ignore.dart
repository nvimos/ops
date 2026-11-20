import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../local/editors.dart';
import '../local/git_repo.dart' show GitException;
import '../local/ignore_edits.dart';
import '../local/local_backend.dart';
import '../local/paths.dart';
import '../local/repo.dart';
import '../local/trash.dart';
import '../timing/ui_timing.dart';
import 'action_queue.dart';
import 'session.dart';
import 'status_store.dart';

/// The sections of the file-first list.
enum AddIgnoreSection { conflicts, staged, changed, untracked }

/// One row of the Add and Ignore list: a file side, not a whole status entry.
class AddIgnoreRow {
  AddIgnoreRow(this.file, this.section);

  final StatusFile file;
  final AddIgnoreSection section;

  String get path => file.path;
  String get key => '${section.name}:${file.path}';

  /// True for a directory row: git prints those with a trailing slash.
  bool get isDirectory => path.endsWith('/');

  /// [path] without the directory's trailing slash, so its base name is not empty.
  String get _clean => isDirectory ? path.substring(0, path.length - 1) : path;

  /// The base name, with a slash for a directory, as in Purrage.
  String get name {
    final slash = _clean.lastIndexOf('/');
    final base = slash < 0 ? _clean : _clean.substring(slash + 1);
    return isDirectory ? '$base/' : base;
  }

  /// The folder before the base name; empty at the repository root.
  String get folder {
    final slash = _clean.lastIndexOf('/');
    return slash < 0 ? '' : _clean.substring(0, slash);
  }

  bool get untracked => section == AddIgnoreSection.untracked;
  bool get conflicted => section == AddIgnoreSection.conflicts;
}

/// An Ignore dialog write: the file it went into, the rules it asked for, and what each one came to
/// (added, or already there). The pane selects the file and centres the first new rule from it.
class IgnoreWrite {
  const IgnoreWrite(this.file, this.patterns, this.appends);

  final IgnoreFileRef file;
  final List<String> patterns;
  final List<IgnoreAppend> appends;
}

/// State for the Add and Ignore mode: one file-first list over the shared
/// status store and action queue. Track, untrack, ignore and delete run through
/// the same queue as Changes; the mode owns only its cursor, selection and
/// filter.
class AddIgnoreState extends ChangeNotifier {
  AddIgnoreState(this.session, {Future<void> Function(List<String> paths)? remove})
    : _remove = remove ?? ((paths) => Trash().send(paths, permanent: !session.deleteToTrash)) {
    store.addListener(notifyListeners);
    store.refreshed.addListener(_onRefreshed);
    store.refresh();
  }

  final Session session;
  final Future<void> Function(List<String> paths) _remove;

  StatusStore get store => session.store;
  ActionQueue get actions => session.actions;

  String filter = '';
  int cursor = 0;
  final Set<String> _selection = {};
  int? _anchor;
  bool _disposed = false;

  /// The last Ignore dialog write, for the panes: select that file, centre its new rule.
  final ignoreWrites = ValueNotifier<IgnoreWrite?>(null);

  /// What the last ignore write did to the list (rows back or now ignored), from the status the
  /// action queue already read; no extra git call.
  IgnoreEffect? lastIgnoreEffect;

  /// The repository on disk the rules engine (ignore, delete) works on: the local backend's own, or,
  /// connected to Neovim, one opened on the root Neovim reports ([ensureRepo]), since Neovim runs on
  /// this machine. Null until that has opened, or when the root is not a git folder here.
  Repo? get repo {
    final b = session.backend;
    if (b is LocalBackend) return b.repo;
    final root = session.repo?.root;
    return root != null && root == _nvimRoot ? _nvimRepo : null;
  }

  Repo? _nvimRepo;
  String? _nvimRoot;
  Future<void>? _opening;

  /// [repo], opening the Neovim session's root first when it changed; a caller that comes while
  /// the open runs waits for the same one.
  Future<Repo?> ensureRepo() async {
    if (session.backend is LocalBackend) return repo;
    final root = session.repo?.root;
    if (root == null) return null;
    if (root != _nvimRoot) {
      _nvimRoot = root;
      _nvimRepo = null;
      _opening = _open(root);
    }
    await _opening;
    return repo;
  }

  Future<void> _open(String root) async {
    try {
      final opened = await Repo.open(root);
      if (_nvimRoot == root) _nvimRepo = opened;
    } on GitException {
      // not a git folder on this machine: ignore and delete stay off
    }
  }

  /// Open [path] (relative to the repository root) in the editor Settings names; a folder opens as a
  /// folder. The error text, or null.
  Future<String?> openInEditor(String path) async {
    final root = session.repo?.root;
    if (root == null) return 'Open needs a local repository.';
    try {
      await session.editors.open(file: '$root/$path', folder: path.endsWith('/'));
      return null;
    } on EditorException catch (e) {
      return '$e';
    }
  }

  /// Every row, in section order and tree order. Built once per status: the store replaces the
  /// [Status] object on every change and never edits one, so the identity is the cache key. Before,
  /// this getter rebuilt and sorted every row on each read, and one cursor move read it a dozen
  /// times (move, selected, actionRows, headersAbove, the build, the pane and the preview).
  List<AddIgnoreRow> get rows {
    final status = store.status;
    if (_rows == null || !identical(status, _rowsOf)) {
      _rowsOf = status;
      _rows = _buildRows(status?.files ?? const <StatusFile>[]);
    }
    return _rows!;
  }

  List<AddIgnoreRow>? _rows;
  Status? _rowsOf;

  List<AddIgnoreRow> _buildRows(List<StatusFile> files) {
    final out = <AddIgnoreRow>[];
    for (final file in files) {
      if (file.conflicted) {
        out.add(AddIgnoreRow(file, AddIgnoreSection.conflicts));
      } else {
        if (file.staged) out.add(AddIgnoreRow(file, AddIgnoreSection.staged));
        if (file.unstaged) out.add(AddIgnoreRow(file, AddIgnoreSection.changed));
        if (file.untracked) out.add(AddIgnoreRow(file, AddIgnoreSection.untracked));
      }
    }
    out.sort((a, b) {
      final bySection = a.section.index.compareTo(b.section.index);
      return bySection != 0 ? bySection : a.path.compareTo(b.path);
    });
    return out;
  }

  /// [rows] that pass the filter, cached for the same rows and filter.
  List<AddIgnoreRow> get visible {
    final all = rows;
    if (_visible == null || !identical(all, _visibleOf) || filter != _visibleFilter) {
      _visibleOf = all;
      _visibleFilter = filter;
      final q = filter.trim().toLowerCase();
      _visible = q.isEmpty ? all : [for (final row in all) if (row.path.toLowerCase().contains(q)) row];
    }
    return _visible!;
  }

  List<AddIgnoreRow>? _visible, _visibleOf;
  String? _visibleFilter;

  AddIgnoreRow? get selected => visible.isEmpty ? null : visible[cursor.clamp(0, visible.length - 1)];

  bool isSelected(AddIgnoreRow row) => _selection.contains(row.key);

  List<AddIgnoreRow> get selectedRows => [for (final row in visible) if (isSelected(row)) row];

  int get selectionCount => _selection.length;

  /// The rows an action works on: the highlighted ones, or the cursor row.
  List<AddIgnoreRow> get actionRows {
    final picked = selectedRows;
    if (picked.isNotEmpty) return picked;
    final row = selected;
    return row == null ? const [] : [row];
  }

  void setFilter(String query) {
    filter = query;
    cursor = 0;
    _anchor = null;
    _selection.clear();
    _selectCursor();
    notifyListeners();
  }

  void move(int delta) {
    if (visible.isEmpty) return;
    UiTiming.instance.span('addIgnore.move').markPainted(); // the key press -> the frame with the new cursor
    cursor = (cursor + delta).clamp(0, visible.length - 1);
    _selection
      ..clear()
      ..add(visible[cursor].key);
    _anchor = cursor;
    notifyListeners();
  }

  /// Shift + arrow: move the cursor and highlight every row from the anchor to it.
  void extend(int delta) {
    if (visible.isEmpty) return;
    click(cursor + delta, shift: true);
  }

  /// Space: add the cursor row to the highlighted ones, or take it out again.
  void toggleCursor() => click(cursor, ctrl: true);

  /// How many rows sit above [index] in the list with its section headers (for scrolling to it).
  int headersAbove(int index) {
    final rows = visible;
    if (rows.isEmpty) return 0;
    var headers = 0;
    AddIgnoreSection? last;
    for (var i = 0; i <= index.clamp(0, rows.length - 1); i++) {
      if (rows[i].section != last) headers++;
      last = rows[i].section;
    }
    return headers;
  }

  void click(int index, {bool ctrl = false, bool shift = false}) {
    if (visible.isEmpty) return;
    final next = index.clamp(0, visible.length - 1);
    final row = visible[next];
    if (shift) {
      final from = _anchor ?? cursor;
      final low = from < next ? from : next;
      final high = from < next ? next : from;
      _selection.clear();
      for (var i = low; i <= high; i++) {
        _selection.add(visible[i].key);
      }
    } else if (ctrl) {
      if (!_selection.remove(row.key)) _selection.add(row.key);
      _anchor = next;
    } else {
      _selection
        ..clear()
        ..add(row.key);
      _anchor = next;
    }
    cursor = next;
    _selectCursor();
    notifyListeners();
  }

  void selectAll() {
    _selection
      ..clear()
      ..addAll(visible.map((row) => row.key));
    _anchor = 0;
    notifyListeners();
  }

  void collapseSelection() {
    final row = selected;
    if (row == null) return;
    _selection
      ..clear()
      ..add(row.key);
    _anchor = cursor;
    notifyListeners();
  }

  Future<ActionResult> trackSelected() {
    final paths = {for (final row in actionRows) if (!row.conflicted) row.path}.toList();
    if (paths.isEmpty) return Future.value(const ActionResult('track', 'nothing to add'));
    return actions.run(
      'track',
      (b) async {
        for (final path in paths) {
          await b.stage(path);
        }
      },
      predict: (files) => [for (final file in files) paths.contains(file.path) ? file.moved(toStaged: true) : file],
      origin: 'Add and Ignore.track -> LocalBackend.stage',
      command: 'git add -- ${paths.take(8).join(' ')}',
      changed: paths.length,
    );
  }

  Future<ActionResult> untrackSelected() {
    final paths = {
      for (final row in actionRows)
        if (!row.conflicted && row.section != AddIgnoreSection.untracked) row.path,
    }.toList();
    if (paths.isEmpty) return Future.value(const ActionResult('untrack', 'nothing to stop tracking'));
    return actions.run(
      'untrack',
      (b) async {
        for (final path in paths) {
          await b.unstage(path);
        }
      },
      predict: (files) => [for (final file in files) paths.contains(file.path) ? file.moved(toStaged: false) : file],
      origin: 'Add and Ignore.untrack -> LocalBackend.unstage',
      command: 'git restore --staged -- ${paths.take(8).join(' ')}',
      changed: paths.length,
    );
  }

  Future<ActionResult> deleteSelected() async {
    final rows = actionRows.where((row) => !row.conflicted).toList();
    if (rows.isEmpty) return const ActionResult('delete', 'nothing to delete');
    final r = await ensureRepo();
    if (r == null) return const ActionResult('delete', 'delete needs a local repository');
    final paths = [for (final row in rows) pathIn(r.path, row.path)];
    return actions.run(
      'delete',
      (b) async => _remove(paths),
      predict: (files) => [for (final file in files) if (!rows.any((row) => row.path == file.path)) file],
      origin: 'Add and Ignore.delete -> Trash',
      command: 'trash ${paths.length} item(s)',
      changed: paths.length,
    );
  }

  /// Write a literal ignore rule for each untracked selected row into [target], through the
  /// backend. Tracked rows stay: a rule does not untrack.
  Future<ActionResult> ignoreSelected(IgnoreFileRef target) => _ignoreRows(target, untrack: false);

  /// The row's eye: [ignoreSelected] for every selected row, and a tracked one is stopped as well
  /// (`git rm --cached`; the file stays on disk), so it leaves the list - an untracked row at once,
  /// a tracked one as a staged deletion until the commit that stops tracking it.
  Future<ActionResult> ignoreAndUntrackSelected(IgnoreFileRef target) => _ignoreRows(target, untrack: true);

  Future<ActionResult> _ignoreRows(IgnoreFileRef target, {required bool untrack}) async {
    final rows = actionRows.where((row) => row.untracked || (untrack && !row.conflicted)).toList();
    if (rows.isEmpty) return const ActionResult('ignore', 'nothing to ignore');
    final tracked = untrack ? {for (final row in rows) if (!row.untracked) row.path}.toList() : const <String>[];
    final r = tracked.isEmpty ? null : await ensureRepo();
    if (tracked.isNotEmpty && r == null) {
      return const ActionResult('ignore', 'untracking a tracked row needs a local repository');
    }
    final paths = rows.map((row) => row.path).toSet().toList();
    final before = store.status?.files ?? const <StatusFile>[];
    var appends = const <IgnoreAppend>[];
    final result = await actions.run(
      'ignore',
      (b) async {
        appends = await b.appendIgnoreLines(target, paths);
        // The rule first, then the untrack, so the file stops showing as tracked and starts to be
        // ignored in the same trip; `git rm --cached` leaves the file where it is.
        if (tracked.isNotEmpty) await r!.untrack(tracked);
      },
      predict: (files) => [for (final file in files) if (!paths.contains(file.path)) file],
      settled: () async => _noteWrite(target, paths, appends),
      origin: 'Add and Ignore.ignore -> RepoBackend.appendIgnoreLines, Repo.untrack',
      command: tracked.isEmpty
          ? '${_targetName(target)} += ${paths.length} rule(s)'
          : '${_targetName(target)} += ${paths.length} rule(s), git rm --cached -- ${tracked.take(8).join(' ')}',
      changed: paths.length,
    );
    lastIgnoreEffect = IgnoreEffect.between(before, store.status?.files ?? const <StatusFile>[]);
    return result;
  }

  /// Write [patterns] (built by the Ignore dialog) into [target]; the rows in [covered] leave the
  /// list at once, a failure puts them back. The write's file and rules reach the open ignore pane,
  /// which selects the file and centres the first new rule.
  Future<ActionResult> ignoreWith(IgnoreFileRef target, List<String> patterns, {required List<String> covered}) async {
    if (patterns.isEmpty) return const ActionResult('ignore', 'nothing to ignore');
    final before = store.status?.files ?? const <StatusFile>[];
    var appends = const <IgnoreAppend>[];
    final result = await actions.run(
      'ignore',
      (b) async => appends = await b.appendIgnoreLines(target, patterns),
      predict: (files) => [for (final file in files) if (!covered.contains(file.path)) file],
      settled: () async => _noteWrite(target, patterns, appends),
      origin: 'Add and Ignore.ignore -> RepoBackend.appendIgnoreLines',
      command: '${_targetName(target)} += ${patterns.join(' ')}',
      changed: covered.length,
    );
    lastIgnoreEffect = IgnoreEffect.between(before, store.status?.files ?? const <StatusFile>[]);
    return result;
  }

  void _noteWrite(IgnoreFileRef target, List<String> patterns, List<IgnoreAppend> appends) {
    if (appends.isEmpty) return;
    ignoreWrites.value = IgnoreWrite(target, patterns, appends);
  }

  static String _targetName(IgnoreFileRef f) => f.exclude ? 'exclude' : f.path.split('/').last;

  void _onRefreshed() {
    final keys = {for (final row in visible) row.key};
    _selection.retainWhere(keys.contains);
    _selectCursor();
    notifyListeners();
  }

  /// A repository is there or can be opened: the local backend's, or the root Neovim reports. The
  /// actions open it on demand ([ensureRepo]), not on every refresh (a git process per refresh, and
  /// one a widget test's fake clock never finishes).
  bool get mayHaveRepo => session.backend is LocalBackend ? repo != null : session.repo?.root != null;

  void _selectCursor() {
    if (_selection.isNotEmpty || visible.isEmpty) return;
    _selection.add(visible[cursor.clamp(0, visible.length - 1)].key);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    store.removeListener(notifyListeners);
    store.refreshed.removeListener(_onRefreshed);
    ignoreWrites.dispose();
    super.dispose();
  }
}
