import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import '../state/session.dart';
import 'archive.dart';
import 'auto_status.dart';
import 'edits.dart';
import 'markdown.dart';
import 'model.dart';
import 'parse.dart';
import '../timing/ui_timing.dart';

/// Every planning file of the repo, parsed and linked. Files are read through Neovim (the backend's
/// files.*), so unsaved edits in Neovim show up too. Reloads on git hints for the planning dirs.
class Workspace extends ChangeNotifier {
  Workspace(this.session) {
    session.gitChanged.addListener(_onGit);
    load();
  }

  final Session session;

  /// The tasks and changes of this project (see [projectOnly]); [allTasks] and [allChanges] hold
  /// every one in the planning folder.
  List<Task> tasks = [];
  List<Change> changes = [];
  List<Task> allTasks = [];
  List<Change> allChanges = [];

  /// Where the planning lives (the repo, or the folder its `.nvimos` names) and this repo's project.
  Tracking? tracking;

  /// The project labels the planning folder knows (`projects:` in backlog/config.yml).
  Set<String> projects = {};

  /// Show only this project's tasks (and their changes); off shows every project's.
  bool projectOnly = true;
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

  /// Parsed models per file (changes per folder), so an edit re-parses only its own file.
  final _taskOf = <String, Task>{};
  final _specOf = <String, Spec>{};
  final _legacyOf = <String, List<LegacyItem>>{};
  final _changeOf = <String, Change?>{};

  /// Edits made so far, and the edit count when each path was last edited: a load that started
  /// before an edit keeps the edited text instead of the older one it read.
  int _edits = 0;
  final _editedAt = <String, int>{};

  /// Our own writes, by path, and when: the git hint they cause doesn't need a reload.
  final _ownWrites = <String, DateTime>{};

  /// Raw lines of a loaded planning file (or null).
  List<String>? file(String path) => _files[path];

  static const dirs = ['backlog', 'openspec', 'legacy'];

  void _onGit() {
    final paths = session.changedPaths.value;
    final relevant =
        !loaded || paths.isEmpty || paths.any((p) => dirs.any((d) => p.startsWith('$d/') || p.contains('/$d/')));
    if (!relevant || (loaded && paths.isNotEmpty && paths.every(_isOwnWrite))) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), load);
  }

  /// A path the app itself wrote in the last few seconds (the hint may name it absolute).
  bool _isOwnWrite(String p) {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 3));
    _ownWrites.removeWhere((_, t) => t.isBefore(cutoff));
    final rel = p.replaceAll(r'\', '/');
    return _ownWrites.keys.any((w) => rel == w || rel.endsWith('/$w'));
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
    final span = UiTiming.instance.span('tasks.load');
    final gen = ++_gen;
    final edits = _edits;
    loading = true;
    _notify();
    try {
      tracking = await _tracking(b);
      final entries = await b.listFiles(dirs);
      final wanted = entries.where((e) => e.path.endsWith('.md') || e.path.endsWith('.yml')).toList();
      final texts = await b.readFiles([...wanted.map((e) => e.path), 'milestones.md', 'index.tsv']);
      if (gen != _gen) return;
      final fresh = {
        for (final t in texts)
          if (t.exists) t.path: t.lines,
      };
      // Edited while this load ran: the edit is newer than what was read.
      for (final MapEntry(key: p, value: at) in _editedAt.entries) {
        if (at > edits && _files[p] != null) fresh[p] = _files[p]!;
      }
      _mtimes = {for (final e in entries) e.path: e.mtime};
      _invalidate(fresh);
      _files = fresh;
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
        span.end();
        loading = false;
        _notify();
        if (_again) {
          _again = false;
          load();
        }
      }
    }
  }

  /// Null with a backend that has no tracking.lua yet (planning in the repo root, no filter).
  Future<Tracking?> _tracking(Backend b) async {
    try {
      return await b.tracking();
    } catch (_) {
      return null;
    }
  }

  /// Drop the parsed models of files whose text differs in [next], or that are gone.
  void _invalidate(Map<String, List<String>> next) {
    for (final p in {..._files.keys, ...next.keys}) {
      final a = _files[p], b = next[p];
      if (a == null || b == null || (!identical(a, b) && !listEquals(a, b))) _forget(p);
    }
  }

  void _forget(String path) {
    _taskOf.remove(path);
    _specOf.remove(path);
    _legacyOf.remove(path);
    final dir = _changeDir(path);
    if (dir != null) _changeOf.remove(dir);
  }

  static final _taskRe = RegExp(r'^backlog/(archive/)?tasks/task-');
  static final _specRe = RegExp(r'^openspec/specs/([^/]+)/spec\.md$');
  static final _changeRe = RegExp(r'^(openspec/changes/(?:archive/)?[^/]+)/');

  /// The change folder a path belongs to (`openspec/changes/<id>` or `.../archive/<dated-id>`).
  static String? _changeDir(String path) {
    final d = _changeRe.firstMatch(path)?.group(1);
    return d == 'openspec/changes/archive' ? null : d;
  }

  /// Forget the models of files that are gone.
  void _prune(Map<String, List<String>> files) {
    _taskOf.removeWhere((p, _) => !files.containsKey(p));
    _specOf.removeWhere((p, _) => !files.containsKey(p));
    _legacyOf.removeWhere((p, _) => !files.containsKey(p));
    final dirs = {for (final p in files.keys) ?_changeDir(p)};
    _changeOf.removeWhere((d, _) => !dirs.contains(d));
  }

  /// Build the models from the file contents in memory. Only files without a parsed model (new or
  /// changed) are parsed again, so an edit costs one file, not the whole repo.
  void _rebuild() => UiTiming.instance.sync('tasks.rebuild', _parseAll);

  void _parseAll() {
    final files = _files;
    final cfg = files['backlog/config.yml'];
    if (cfg != null) {
      final (st, name) = parseBacklogConfig(cfg);
      statuses = st;
      projectName = name;
      projects = parseBacklogProjects(cfg).toSet();
    }
    final changeFiles = <String, Map<String, List<String>>>{};
    for (final MapEntry(key: p, value: lines) in files.entries) {
      if (_taskRe.hasMatch(p)) {
        _taskOf[p] ??= parseTask(p, lines, mtime: _mtimes[p]);
      } else if (_specRe.hasMatch(p)) {
        _specOf[p] ??= parseSpec(p.split('/')[2], Doc(p, lines));
      } else if (p.startsWith('legacy/') && p.endsWith('.md')) {
        _legacyOf[p] ??= parseLegacy(p.substring(7), lines);
      } else if (_changeDir(p) case final dir? when !_changeOf.containsKey(dir)) {
        changeFiles.putIfAbsent(dir, () => {})[p] = lines;
      }
    }
    for (final MapEntry(key: dir, value: fs) in changeFiles.entries) {
      _changeOf[dir] = parseChanges(fs, _mtimes).firstOrNull;
    }
    _prune(files);
    allTasks = _sortedBy(_taskOf.values, (t) => t.number);
    allChanges = _sortedBy([for (final c in _changeOf.values) ?c], (c) => _num(c.id));
    _filter();
    specs = _specOf.values.toList()..sort((a, b) => a.capability.compareTo(b.capability));
    legacy = [for (final p in files.keys) ...?_legacyOf[p]];
    final ms = files['milestones.md'];
    milestonesFromFile = ms != null;
    milestones = ms != null ? parseMilestones(ms) : monthlyMilestones(changes);
  }

  // Projects ----------------------------------------------------------------------------------

  /// This repo's project in a shared planning folder, if `.nvimos` names one.
  String? get project => tracking?.project;

  /// Whether the project filter applies: a project is named and [projectOnly] is on.
  bool get filtering => project != null && projectOnly;

  /// A task belongs to the project when it has its label, or no known project's label (shared).
  /// Without `projects:` in config.yml, only tasks with the label belong.
  bool belongs(Task t) {
    final p = project;
    if (p == null || t.labels.contains(p)) return true;
    return projects.isNotEmpty && !t.labels.any(projects.contains);
  }

  /// A change belongs with its task; one without a task is shared.
  bool changeBelongs(Change c) {
    final t = c.taskId == null ? null : task(c.taskId!);
    return t == null || belongs(t);
  }

  void _filter() {
    tasks = filtering ? allTasks.where(belongs).toList() : allTasks;
    changes = filtering ? allChanges.where(changeBelongs).toList() : allChanges;
  }

  void setProjectOnly(bool on) {
    projectOnly = on;
    _filter();
    milestones = milestonesFromFile ? milestones : monthlyMilestones(changes);
    _notify();
  }

  /// [path] (relative to the planning folder) as an absolute path, for a program started outside
  /// Neovim (a new nvim-qt).
  String fullPath(String path) {
    final t = tracking;
    return t == null || path.contains(':/') || path.startsWith('/') ? path : '${t.root}/$path';
  }

  /// [path] (relative to the planning folder) as Neovim should open it: absolute when the planning
  /// folder is outside the repo.
  String absolute(String path) {
    final t = tracking;
    return t == null || !t.elsewhere ? path : '${t.root}/$path';
  }

  // Edits -------------------------------------------------------------------------------------

  /// Apply edits to a file: in memory first (the UI updates at once), then through Neovim. If the
  /// write is refused (the file changed, unsaved buffer), reload and return the error.
  Future<String?> edit(String path, List<LineEdit> edits) async {
    final lines = _files[path];
    if (lines == null) return '$path is not loaded';
    final span = UiTiming.instance.span('tasks.edit');
    _files[path] = applyEdits(lines, edits);
    _editedAt[path] = ++_edits;
    _ownWrites[path] = DateTime.now();
    _forget(path);
    _rebuild();
    _notify();
    span.mark('optimistic');
    span.markPainted();
    final err = await session.run((b) => b.setLines(path, edits));
    _ownWrites[path] = DateTime.now(); // its git hint comes after the write
    span.mark('saved');
    if (err != null) await load();
    span.end();
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

  /// The last status the app set by itself after a tick (see [toggleCheck]); the view offers Undo.
  final autoStatus = ValueNotifier<AutoStatus?>(null);

  /// Toggle a checkbox. Ticking the last open box of a task (or of its change's tasks.md) moves the
  /// task on: to Needs Test when only hand checks are left, to Done when nothing is.
  Future<String?> toggleCheck(String path, Check c) async {
    final lines = _files[path];
    if (lines == null || c.line >= lines.length) return '$path changed; refresh';
    final err = await edit(path, [toggleCheckEdit(lines, c)]);
    if (err != null || c.done) return err;
    return _autoStatus(path);
  }

  /// After a tick in [path]: the task's checks, or its change's Build / Verify groups.
  Future<String?> _autoStatus(String path) async {
    final task = _taskOf[path];
    final change = task == null ? allChanges.where((c) => c.tasks?.path == path).firstOrNull : null;
    final t = task ?? (change == null ? null : taskFor(change));
    if (t == null) return null;
    final groups = change?.checkGroups ?? [];
    bool isVerify(String title) => title.toLowerCase().contains('verify');
    final next = autoStatusAfterTick(
      status: t.status,
      build: task != null
          ? [...task.acceptance, ...task.definitionOfDone]
          : [for (final (title, cs) in groups) if (!isVerify(title)) ...cs],
      verify: task != null ? task.verify : [for (final (title, cs) in groups) if (isVerify(title)) ...cs],
      statuses: statuses,
    );
    if (next == null) return null;
    final from = t.status;
    final err = await setTaskStatus(t, next);
    if (err == null) autoStatus.value = AutoStatus(t.id, from, next);
    return err;
  }

  /// Undo an [AutoStatus]: put the task's status back.
  Future<String?> undoAutoStatus(AutoStatus a) async {
    final t = task(a.taskId);
    return t == null ? null : setTaskStatus(t, a.from);
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

  /// What the agent is asked to do for "New change".
  String newChangePrompt(String sentence) {
    final n = nextTaskNumber;
    final t = tracking;
    return [
      'Draft an OpenSpec change for this, in this repo, and stop there (no code):',
      '',
      sentence.trim(),
      '',
      if (t != null && t.elsewhere) ...[
        'The planning files are in ${t.root} (named by ${t.file}); the paths below are relative to it.',
        '',
      ],
      if (project != null) ...['Give the task the label "$project" (this repo\'s project there).', ''],
      'Follow openspec/config.yaml and the layout of the other folders in openspec/changes/:',
      '- openspec/changes/<id>/proposal.md with "# <title>", "Status: To Do (backlog TASK-$n)", ## Why,',
      '  ## What Changes, ## Impact;',
      '- openspec/changes/<id>/tasks.md with "## 1. Build" and "## 2. Verify" checklists, kept apart;',
      '- spec deltas in openspec/changes/<id>/specs/<capability>/spec.md (## ADDED / MODIFIED / REMOVED',
      '  Requirements, ### Requirement: and #### Scenario: blocks) only if behavior changes;',
      '- the matching Backlog.md task backlog/tasks/task-$n - <slug>.md (front matter id: TASK-$n,',
      '  title, status: To Do, created_date, labels, dependencies) with ## Description and ## Verify,',
      '  like the other task files;',
      '- the row for TASK-$n in index.tsv if the file exists.',
      'Use <id> = "$n-<short-slug>". Touch nothing else.',
    ].join('\n');
  }

  /// Start an agent (claude -p) that drafts a change and its task. Returns (error, job id).
  Future<(String?, int?)> newChange(String sentence) async {
    int? id;
    final err = await session.run((b) async {
      id = await b.startJob(
        'claude',
        ['-p', '--permission-mode', 'acceptEdits', '--allowedTools', 'Read,Write,Edit,Glob,Grep'],
        stdin: newChangePrompt(sentence),
        label: 'new change: ${sentence.trim()}',
      );
    });
    return (err, id);
  }

  /// Over every project's tasks: they share the numbers.
  int get nextTaskNumber => allTasks.fold<int>(0, (n, t) => t.number > n ? t.number : n) + 1;

  /// Create a task file (Backlog.md format). Returns (error, new task id).
  Future<(String?, String)> createTask({
    required String title,
    String status = 'To Do',
    List<String> labels = const [],
    List<String> description = const [],
    List<String> originalNotes = const [],
  }) async {
    final n = nextTaskNumber;
    final p = project;
    final (path, lines) = newTaskFile(
      number: n,
      title: title,
      status: status,
      labels: p == null || labels.contains(p) ? labels : [p, ...labels],
      description: description,
      originalNotes: originalNotes,
    );
    final err = await session.run((b) => b.create(path, lines));
    if (err == null) {
      _files[path] = lines;
      _forget(path);
      _rebuild();
      _notify();
    }
    return (err, 'TASK-$n');
  }

  /// Sort by a key computed once per item (task numbers come from parsing the front matter).
  static List<T> _sortedBy<T>(Iterable<T> items, int Function(T) key) {
    final keyed = [for (final x in items) (key(x), x)]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final k in keyed) k.$2];
  }

  static int _num(String id) => int.tryParse(RegExp(r'^\d+').firstMatch(id)?.group(0) ?? '') ?? 1 << 30;

  String get defaultBranch {
    final names = branches?.list.map((b) => b.name).toSet() ?? {};
    return names.contains('main') ? 'main' : (names.contains('master') ? 'master' : (branches?.current ?? 'main'));
  }

  /// Link a task to a branch by hand (null unlinks); counts its commits.
  Future<void> linkBranch(Task t, String? branch) async {
    if (branch == null) {
      links.remove(t.id);
    } else {
      links[t.id] = branch;
    }
    await _countAhead();
    _notify();
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

  Task? task(String id) => allTasks.where((t) => t.id.toUpperCase() == id.toUpperCase()).firstOrNull;

  Change? changeFor(Task t) => changes
      .where((c) => c.taskId == t.id.toUpperCase())
      .fold<Change?>(null, (best, c) => best == null || (best.archived && !c.archived) ? c : best);

  Task? taskFor(Change c) => c.taskId == null ? null : task(c.taskId!);

  /// Branches linked by hand (task id -> branch); they win over the name rules.
  final links = <String, String>{};

  /// The agent branch of a task: linked by hand, else its id (task-17, task_17) or its change's id
  /// in the branch name.
  String? branchFor(Task t) {
    final list = branches?.list ?? [];
    final manual = links[t.id];
    if (manual != null && list.any((b) => b.name == manual)) return manual;
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
    autoStatus.dispose();
    super.dispose();
  }
}
