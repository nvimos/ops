import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../local/git_repo.dart';
import '../local/local_backend.dart';
import '../local/paths.dart';
import '../local/repo.dart';
import '../local/trash.dart';
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
  String get name {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  String get folder {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  bool get untracked => section == AddIgnoreSection.untracked;
  bool get conflicted => section == AddIgnoreSection.conflicts;
}

/// State for the Add and Ignore mode: one file-first list over the shared
/// status store and action queue. Track, untrack, ignore and delete run through
/// the same queue as Changes; the mode owns only its cursor, selection and
/// filter.
class AddIgnoreState extends ChangeNotifier {
  AddIgnoreState(this.session, {Future<void> Function(List<String> paths)? remove})
      : _remove = remove ?? Trash().send {
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

  Repo? get repo => session.backend is LocalBackend ? (session.backend! as LocalBackend).repo : null;

  /// Every row, in section order and tree order.
  List<AddIgnoreRow> get rows {
    final files = store.status?.files ?? const <StatusFile>[];
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

  List<AddIgnoreRow> get visible {
    final q = filter.trim().toLowerCase();
    return q.isEmpty ? rows : [for (final row in rows) if (row.path.toLowerCase().contains(q)) row];
  }

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

  Future<ActionResult> deleteSelected() {
    final rows = actionRows.where((row) => !row.conflicted).toList();
    if (rows.isEmpty) return Future.value(const ActionResult('delete', 'nothing to delete'));
    final r = repo;
    if (r == null) return Future.value(const ActionResult('delete', 'delete needs a local repository'));
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

  /// Write a literal ignore rule for each untracked selected row into [target]
  /// (an absolute `.gitignore` path). Tracked rows stay: a rule does not untrack.
  Future<ActionResult> ignoreSelected(String target) {
    final rows = actionRows.where((row) => row.untracked).toList();
    if (rows.isEmpty) return Future.value(const ActionResult('ignore', 'nothing to ignore'));
    final r = repo;
    if (r == null) return Future.value(const ActionResult('ignore', 'ignore needs a local repository'));
    final paths = rows.map((row) => row.path).toSet().toList();
    return actions.run(
      'ignore',
      (b) async {
        final existing = await r.checkIgnoreAll(paths);
        final patterns = [for (final path in paths) if (!existing.containsKey(path)) path];
        if (patterns.isNotEmpty) await r.appendIgnoreLines(target, patterns);
      },
      predict: (files) => [for (final file in files) if (!paths.contains(file.path)) file],
      origin: 'Add and Ignore.ignore -> LocalBackend.appendIgnoreLines',
      command: '${target.split(RegExp(r'[\\/]')).last} += ${paths.length} rule(s)',
      changed: paths.length,
    );
  }

  /// Write [patterns] (built by the Ignore dialog) into [target]; the rows in [covered] leave the
  /// list at once, a failure puts them back.
  Future<ActionResult> ignoreWith(String target, List<String> patterns, {required List<String> covered}) {
    final r = repo;
    if (r == null) return Future.value(const ActionResult('ignore', 'ignore needs a local repository'));
    if (patterns.isEmpty) return Future.value(const ActionResult('ignore', 'nothing to ignore'));
    return actions.run(
      'ignore',
      (b) async => r.appendIgnoreLines(target, patterns),
      predict: (files) => [for (final file in files) if (!covered.contains(file.path)) file],
      origin: 'Add and Ignore.ignore -> LocalBackend.appendIgnoreLines',
      command: '${target.split(RegExp(r'[\\/]')).last} += ${patterns.join(' ')}',
      changed: covered.length,
    );
  }

  /// The rules git already uses for the selected rows, for the dialog preview.
  Future<Map<String, IgnoreMatch>> alreadyIgnored() async {
    final r = repo;
    if (r == null || actionRows.isEmpty) return const {};
    return r.checkIgnoreAll(actionRows.map((row) => row.path));
  }

  String? get rootIgnore => repo == null ? null : '${repo!.path}/.gitignore';

  void _onRefreshed() {
    final keys = {for (final row in visible) row.key};
    _selection.retainWhere(keys.contains);
    _selectCursor();
    notifyListeners();
  }

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
    super.dispose();
  }
}
