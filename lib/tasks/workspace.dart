import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../state/session.dart';
import 'archive.dart';
import 'edits.dart';
import 'markdown.dart';
import 'model.dart';
import 'parse.dart';

/// Every planning file of the repo, parsed and linked. Files are read through Neovim (the backend's
/// files.*), so unsaved edits in Neovim show up too. Reloads on git hints for the planning dirs.
class Workspace extends ChangeNotifier {
  Workspace(this.session) {
    session.gitChanged.addListener(_onGit);
    load();
  }

  final Session session;

  List<Task> tasks = [];
  List<Change> changes = [];
  List<Spec> specs = [];
  List<LegacyItem> legacy = [];
  List<Milestone> milestones = [];
  bool milestonesFromFile = false;
  List<String> statuses = defaultStatuses;
  String projectName = '';
  Branches? branches;
  bool loading = false;
  bool loaded = false;
  String? error;

  /// Commits ahead of the default branch, per branch name (filled for linked branches).
  final ahead = <String, int>{};

  Timer? _debounce;
  bool _disposed = false;
  int _gen = 0;
  bool _again = false;
  Map<String, List<String>> _files = {};
  Map<String, DateTime> _mtimes = {};

  /// Raw lines of a loaded planning file (or null).
  List<String>? file(String path) => _files[path];

  static const dirs = ['backlog', 'openspec', 'legacy'];

  void _onGit() {
    final paths = session.changedPaths.value;
    final relevant =
        !loaded || paths.isEmpty || paths.any((p) => dirs.any((d) => p.startsWith('$d/') || p.contains('/$d/')));
    if (!relevant) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), load);
  }

  /// Reload everything. A call while a load runs queues one more load after it, so a stream of
  /// hints can't keep restarting it.
  Future<void> load() async {
    final b = session.backend;
    if (b == null) return;
    if (loading) {
      _again = true;
      return;
    }
    final gen = ++_gen;
    loading = true;
    _notify();
    try {
      final entries = await b.listFiles(dirs);
      final wanted = entries.where((e) => e.path.endsWith('.md') || e.path.endsWith('.yml')).toList();
      final texts = await b.readFiles([...wanted.map((e) => e.path), 'milestones.md', 'index.tsv']);
      if (gen != _gen) return;
      _mtimes = {for (final e in entries) e.path: e.mtime};
      _files = {
        for (final t in texts)
          if (t.exists) t.path: t.lines,
      };
      _rebuild();
      branches = await b.branches();
      await _countAhead();
      if (gen != _gen) return;
      error = null;
      loaded = true;
    } catch (e) {
      if (gen == _gen) error = '$e';
    } finally {
      if (gen == _gen) {
        loading = false;
        _notify();
        if (_again) {
          _again = false;
          load();
        }
      }
    }
  }

  /// Parse every model from the file contents in memory.
  void _rebuild() {
    final files = _files;
    final cfg = files['backlog/config.yml'];
    if (cfg != null) {
      final (st, name) = parseBacklogConfig(cfg);
      statuses = st;
      projectName = name;
    }
    tasks = [
      for (final e in files.entries)
        if (RegExp(r'^backlog/(archive/)?tasks/task-').hasMatch(e.key))
          parseTask(e.key, e.value, mtime: _mtimes[e.key]),
    ]..sort((a, b) => a.number.compareTo(b.number));
    changes = parseChanges(files, _mtimes)..sort((a, b) => _num(a.id).compareTo(_num(b.id)));
    specs = [
      for (final e in files.entries)
        if (RegExp(r'^openspec/specs/([^/]+)/spec\.md$').hasMatch(e.key))
          parseSpec(e.key.split('/')[2], Doc(e.key, e.value)),
    ]..sort((a, b) => a.capability.compareTo(b.capability));
    legacy = [
      for (final e in files.entries)
        if (e.key.startsWith('legacy/') && e.key.endsWith('.md')) ...parseLegacy(e.key.substring(7), e.value),
    ];
    final ms = files['milestones.md'];
    milestonesFromFile = ms != null;
    milestones = ms != null ? parseMilestones(ms) : monthlyMilestones(changes);
  }

  // Edits -------------------------------------------------------------------------------------

  /// Apply edits to a file: in memory first (the UI updates at once), then through Neovim. If the
  /// write is refused (the file changed, unsaved buffer), reload and return the error.
  Future<String?> edit(String path, List<LineEdit> edits) async {
    final lines = _files[path];
    if (lines == null) return '$path is not loaded';
    _files[path] = applyEdits(lines, edits);
    _rebuild();
    _notify();
    final err = await session.run((b) => b.setLines(path, edits));
    if (err != null) await load();
    return err;
  }

  /// Status of a task, kept in sync in its change's proposal and in index.tsv.
  Future<String?> setTaskStatus(Task t, String status) async {
    if (t.status == status) return null;
    final err = await edit(t.path, [taskStatusEdit(t, status)]);
    if (err != null) return err;
    final c = changeFor(t);
    final ce = c == null ? null : changeStatusEdit(c, status);
    if (ce != null) {
      final e = await edit(c!.proposal!.path, [ce]);
      if (e != null) return e;
    }
    final index = _files['index.tsv'];
    final ie = index == null ? null : indexStatusEdit(index, t.id, status);
    if (ie != null) return edit('index.tsv', [ie]);
    return null;
  }

  Future<String?> setTaskPriority(Task t, String priority) =>
      t.priority == priority ? Future.value(null) : edit(t.path, [taskPriorityEdit(t, priority)]);

  Future<String?> toggleCheck(String path, Check c) {
    final lines = _files[path];
    if (lines == null || c.line >= lines.length) return Future.value('$path changed; refresh');
    return edit(path, [toggleCheckEdit(lines, c)]);
  }

  /// Archive a change: `openspec archive` when the CLI is installed; otherwise merge its deltas
  /// into `openspec/specs/<capability>/spec.md`, mark it (and its task) Done, and move the folder to
  /// `openspec/changes/archive/<date>-<id>`.
  Future<String?> archive(Change c, {DateTime? now}) async {
    final b = session.backend;
    if (b == null) return 'not connected';
    final version = await b.cli('openspec', ['--version']);
    if (version.code == 0) {
      final r = await b.cli('openspec', ['archive', c.id, '--yes']);
      await load();
      return r.code == 0 ? null : (r.stderr.isEmpty ? r.stdout : r.stderr).trim();
    }
    final t = taskFor(c);
    if (t != null && t.status != 'Done') {
      final err = await setTaskStatus(t, 'Done');
      if (err != null) return err;
    } else if (c.status != 'Done') {
      final fresh = changes.firstWhere((x) => x.dir == c.dir, orElse: () => c);
      final e = changeStatusEdit(fresh, 'Done');
      if (e != null) {
        final err = await edit(fresh.proposal!.path, [e]);
        if (err != null) return err;
      }
    }
    final byCap = <String, List<Delta>>{};
    for (final d in c.deltas) {
      byCap.putIfAbsent(d.capability, () => []).add(d);
    }
    for (final e in byCap.entries) {
      final path = 'openspec/specs/${e.key}/spec.md';
      final old = _files[path];
      final merged = mergeDeltas(old, e.key, c.id, e.value);
      final err = await session.run(
        (b) => old == null ? b.create(path, merged) : b.setLines(path, [LineEdit(0, old.length, merged, expect: old)]),
      );
      if (err != null) return err;
    }
    final err = await session.run((b) => b.move(c.dir, archiveDir(c, now ?? DateTime.now())));
    await load();
    return err;
  }

  int get nextTaskNumber => tasks.fold<int>(0, (n, t) => t.number > n ? t.number : n) + 1;

  /// Create a task file (Backlog.md format). Returns (error, new task id).
  Future<(String?, String)> createTask({
    required String title,
    String status = 'To Do',
    List<String> labels = const [],
    List<String> description = const [],
    List<String> originalNotes = const [],
  }) async {
    final n = nextTaskNumber;
    final (path, lines) = newTaskFile(
      number: n,
      title: title,
      status: status,
      labels: labels,
      description: description,
      originalNotes: originalNotes,
    );
    final err = await session.run((b) => b.create(path, lines));
    if (err == null) {
      _files[path] = lines;
      _rebuild();
      _notify();
    }
    return (err, 'TASK-$n');
  }

  static int _num(String id) => int.tryParse(RegExp(r'^\d+').firstMatch(id)?.group(0) ?? '') ?? 1 << 30;

  String get defaultBranch {
    final names = branches?.list.map((b) => b.name).toSet() ?? {};
    return names.contains('main') ? 'main' : (names.contains('master') ? 'master' : (branches?.current ?? 'main'));
  }

  Future<void> _countAhead() async {
    final b = session.backend;
    if (b == null) return;
    final linked = <String>{for (final t in tasks) ?branchFor(t)};
    for (final name in linked) {
      try {
        ahead[name] = (await b.log(defaultBranch, name)).length;
      } catch (_) {}
    }
  }

  Task? task(String id) => tasks.where((t) => t.id.toUpperCase() == id.toUpperCase()).firstOrNull;

  Change? changeFor(Task t) => changes
      .where((c) => c.taskId == t.id.toUpperCase())
      .fold<Change?>(null, (best, c) => best == null || (best.archived && !c.archived) ? c : best);

  Task? taskFor(Change c) => c.taskId == null ? null : task(c.taskId!);

  /// The agent branch of a task: its id (task-17, task_17) or its change's id in the branch name.
  String? branchFor(Task t) {
    final list = branches?.list ?? [];
    final n = t.number;
    final re = RegExp('task[-_]?$n(?!\\d)', caseSensitive: false);
    final change = changeFor(t);
    for (final b in list) {
      if (b.name == defaultBranch) continue;
      if (re.hasMatch(b.name)) return b.name;
      if (change != null && b.name.toLowerCase().contains(change.id.toLowerCase())) return b.name;
    }
    return null;
  }

  List<String> get labels {
    final s = <String>{for (final t in tasks) ...t.labels};
    return s.toList()..sort();
  }

  /// Changes that ever touched a requirement (by name), newest first.
  List<(Change, Delta)> changesTouching(String requirement) {
    final out = <(Change, Delta)>[];
    for (final c in changes) {
      for (final d in c.deltas) {
        if (d.requirement.name.toLowerCase() == requirement.toLowerCase()) out.add((c, d));
      }
    }
    out.sort((a, b) => (b.$1.archiveDate ?? DateTime(9999)).compareTo(a.$1.archiveDate ?? DateTime(9999)));
    return out;
  }

  /// Archived changes of a milestone (between the previous milestone's date and this one's).
  List<Change> changesIn(Milestone m) {
    final i = milestones.indexOf(m);
    final from = i > 0 ? milestones[i - 1].date : null;
    return changes.where((c) {
      final d = c.archiveDate;
      if (d == null) return false;
      return (from == null || d.isAfter(from)) && (m.date == null || !d.isAfter(m.date!));
    }).toList();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _debounce?.cancel();
    session.gitChanged.removeListener(_onGit);
    super.dispose();
  }
}
