import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/models.dart';
import '../../state/nvim_launcher.dart';
import '../../state/prefs.dart';
import '../../state/session.dart';
import '../../tasks/browser.dart';
import '../../tasks/markdown.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../error_view.dart';
import '../key_sequence.dart';
import '../widgets.dart';
import 'change_detail.dart';
import 'dialogs.dart';
import 'legacy_detail.dart';
import 'milestone_detail.dart';
import 'rows.dart';
import 'spec_detail.dart';
import 'task_detail.dart';
import 'tasks_nav.dart';

export '../../tasks/browser.dart' show ChangeKey, LegacyKey, SpecKey, MilestoneKey, TView;

/// The Tasks mode: a Linear-style workspace over the repo's OpenSpec and Backlog.md files.
///
/// Page: owns dialogs, keys and event handlers; [TaskBrowser] holds what is shown and selected,
/// [Workspace] the files.
class TasksView extends StatefulWidget {
  const TasksView({super.key, required this.ws, this.onReview});

  final Workspace ws;
  final void Function(Task task, String branch)? onReview;

  @override
  State<TasksView> createState() => TasksViewState();
}

class TasksViewState extends State<TasksView> implements TaskActions {
  final prefs = Prefs.load();
  late final browser = TaskBrowser(widget.ws, lastSeen: lastSeen);
  Session? _session;

  final focus = FocusNode(debugLabel: 'tasks');
  final filterFocus = FocusNode(debugLabel: 'tasks filter');
  final filter = TextEditingController();
  final scroll = ScrollController();
  late final _keys = KeySequence({
    'gg': () => _moveTo(first: true),
    'G': () => _moveTo(first: false),
    'o': _openSelectedInNeovim,
  });

  /// Jobs this view started, waiting for their `finished` event.
  final _waiting = <int>{};
  Set<String> _changesBefore = {};

  Workspace get ws => widget.ws;
  Session get session => _session!;
  Object? get selected => browser.selected;
  String get _repoKey => session.repo?.root ?? 'repo';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    _session = SessionScope.read(context);
    session.jobs.addListener(_onJobs);
    ws.links.addAll(prefs.branchLinks(_repoKey));
  }

  @override
  void dispose() {
    _session?.jobs.removeListener(_onJobs);
    _keys.dispose();
    browser.dispose();
    focus.dispose();
    filterFocus.dispose();
    filter.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _snack(String? err) {
    if (mounted) showActionError(context, err);
  }

  // Inbox and jobs -------------------------------------------------------------------------------

  /// When the inbox was last marked seen; the first visit of a repo counts as seen now.
  DateTime lastSeen() {
    final t = prefs.lastSeen(_repoKey);
    if (t != null) return t;
    final now = DateTime.now();
    prefs.setLastSeen(_repoKey, now);
    return now;
  }

  void markSeen() {
    prefs.setLastSeen(_repoKey, DateTime.now());
    browser.refresh();
  }

  void _onJobs() {
    for (final id in [..._waiting]) {
      final j = session.jobs.value[id];
      if (j == null || j.running) continue;
      _waiting.remove(id);
      j.code == 0 ? _agentDone() : _snack('The agent failed (${j.code}): ${_lastLine(j)}');
    }
  }

  static String _lastLine(Job j) => (j.stderr.isNotEmpty ? j.stderr : j.stdout).trim().split('\n').last;

  Future<void> _agentDone() async {
    await ws.load();
    final fresh = ws.changes.where((c) => !_changesBefore.contains(c.dir)).toList();
    if (fresh.isEmpty) return _snack('The agent finished but wrote no change.');
    browser.showView(TView.changes);
    browser.select(ChangeKey(fresh.first.dir));
    _snack('Drafted: ${fresh.first.title}');
  }

  void _cancelJob(Job j) => session.run((b) => b.cancelJob(j.id)).then(_snack);

  // Dialogs --------------------------------------------------------------------------------------

  Future<T?> _dialog<T>(Widget dialog) async {
    final r = await showDialog<T>(context: context, builder: (_) => dialog);
    focus.requestFocus();
    return r;
  }

  Future<void> archive(Change c) async {
    if (await _dialog<bool>(ArchiveDialog(lines: ws.archiveLines(c))) != true) return;
    final err = await ws.archive(c);
    _snack(err);
    if (err == null) browser.close();
  }

  Future<void> newChange() async {
    final sentence = await _dialog<String>(const NewChangeDialog());
    if (sentence == null || sentence.isEmpty) return;
    _changesBefore = {for (final c in ws.changes) c.dir};
    final (err, id) = await ws.newChange(sentence);
    if (err != null) return _snack(err);
    if (id != null) _waiting.add(id);
    _snack('An agent is drafting the change; it shows up here when done.');
  }

  Future<void> promote(LegacyItem l) {
    final d = promoteDraft(l);
    return createTask(title: d.title, labels: d.labels, notes: d.notes);
  }

  Future<void> createTask({String title = '', List<String> labels = const [], List<String> notes = const []}) async {
    final r = await _dialog<NewTask>(NewTaskDialog(statuses: ws.statuses, title: title, labels: labels));
    if (r == null || r.title.trim().isEmpty) return;
    final (err, id) = await ws.createTask(
      title: r.title.trim(),
      status: r.status,
      labels: r.labels,
      description: r.description.isEmpty ? [] : r.description.split('\n'),
      originalNotes: notes,
    );
    _snack(err);
    if (err != null) return;
    browser.showStatus(null);
    browser.select(id);
  }

  Future<void> openPalette() async => (await _dialog<PaletteEntry>(Palette(_paletteEntries())))?.run();

  List<PaletteEntry> _paletteEntries() {
    final t = browser.selectedTask;
    return [
      PaletteEntry('New task', 'C', Icons.add, createTask),
      PaletteEntry('New change (an agent drafts it)', 'agent', Icons.auto_awesome, newChange),
      for (final n in browser.navTasks()) PaletteEntry(n.label, 'view', Icons.task_alt, () => browser.go(n)),
      for (final n in browser.navSources()) PaletteEntry(n.label, 'view', Icons.description_outlined, () => browser.go(n)),
      if (t != null) ...[
        for (final s in ws.statuses) PaletteEntry('Set status: $s', t.id, Icons.flag_outlined, () => setStatus(t, s)),
        PaletteEntry('Open ${t.id} in Neovim', 'file', Icons.open_in_new, () => openInNeovim(t.path, 1)),
      ],
      for (final x in ws.tasks) PaletteEntry('${x.id}  ${x.title}', x.status, Icons.task_alt, () => openTask(x.id)),
      for (final c in ws.changes.where((c) => !c.archived))
        PaletteEntry(c.title, 'change', Icons.description_outlined, () => openChange(c)),
    ];
  }

  // TaskActions ----------------------------------------------------------------------------------

  @override
  void openTask(String id) => ws.task(id) == null ? _snack('$id not found') : browser.select(id);

  @override
  void openChange(Change c) => browser.select(ChangeKey(c.dir));

  @override
  void close() => browser.close();

  /// a: this project's tasks / every project's in the shared planning folder.
  void toggleProjectOnly() => ws.setProjectOnly(!ws.projectOnly);

  /// Open a file in the connected Neovim; with Ctrl held (Ctrl+click), in a new nvim-qt instead.
  @override
  void openInNeovim(String path, int line) {
    if (HardwareKeyboard.instance.isControlPressed) {
      openInQt(ws.fullPath(path), line).then(_snack);
    } else {
      session.run((b) => b.open(ws.absolute(path), line)).then(_snack);
    }
  }

  @override
  Future<void> setStatus(Task t, String status) async => _snack(await ws.setTaskStatus(t, status));

  @override
  Future<void> setPriority(Task t, String priority) async => _snack(await ws.setTaskPriority(t, priority));

  @override
  Future<void> toggleCheck(String path, Check c) async => _snack(await ws.toggleCheck(path, c));

  @override
  Future<void> review(Task t, String branch) async => widget.onReview?.call(t, branch);

  @override
  Future<void> linkBranch(Task t, String? branch) async {
    await ws.linkBranch(t, branch);
    prefs.setBranchLinks(_repoKey, Map.of(ws.links));
  }

  // Keys -----------------------------------------------------------------------------------------

  void move(int delta) => _scrollTo(browser.move(delta));

  void _moveTo({required bool first}) => move(first ? -1 << 20 : 1 << 20);

  void _page(int dir) {
    final view = scroll.hasClients ? scroll.position.viewportDimension : 400.0;
    move(dir * (view / 2 / TaskRows.rowHeight).floor());
  }

  void _scrollTo(int? index) {
    if (index == null || !scroll.hasClients) return;
    final top = index * TaskRows.rowHeight, bottom = top + TaskRows.rowHeight;
    final view = scroll.position.viewportDimension, off = scroll.offset;
    if (top < off) scroll.jumpTo(top);
    if (bottom > off + view) scroll.jumpTo(bottom - view);
  }

  void cycleStatus() {
    final t = browser.selectedTask, s = browser.nextStatus();
    if (t != null && s != null) setStatus(t, s);
  }

  void cyclePriority() {
    final t = browser.selectedTask, p = browser.nextPriority();
    if (t != null && p != null) setPriority(t, p);
  }

  /// `o`: the selected record's file in Neovim.
  void _openSelectedInNeovim() {
    final loc = _location(browser.selected);
    if (loc != null) openInNeovim(loc.$1, loc.$2);
  }

  (String, int)? _location(Object? sel) => switch (sel) {
    final String id => ws.task(id) == null ? null : (ws.task(id)!.path, 1),
    ChangeKey(:final dir) => ('$dir/proposal.md', 1),
    final LegacyKey k => ('legacy/${k.file}', k.line + 1),
    _ => null,
  };

  KeyEventResult onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (filterFocus.hasFocus) return _filterKey(e.logicalKey);
    final action = switch (e.logicalKey) {
      LogicalKeyboardKey.keyK when hw.isControlPressed => openPalette,
      LogicalKeyboardKey.keyD when hw.isControlPressed => () => _page(1),
      LogicalKeyboardKey.keyU when hw.isControlPressed => () => _page(-1),
      _ when hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed => null,
      LogicalKeyboardKey.keyJ || LogicalKeyboardKey.arrowDown => () => move(1),
      LogicalKeyboardKey.keyK || LogicalKeyboardKey.arrowUp => () => move(-1),
      LogicalKeyboardKey.enter when browser.selected == null => () => move(1),
      LogicalKeyboardKey.escape when browser.selected != null => close,
      LogicalKeyboardKey.slash || LogicalKeyboardKey.tab => filterFocus.requestFocus,
      LogicalKeyboardKey.keyC => createTask,
      LogicalKeyboardKey.keyS => cycleStatus,
      LogicalKeyboardKey.keyP => cyclePriority,
      LogicalKeyboardKey.keyA when ws.project != null => toggleProjectOnly,
      _ => null,
    };
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    return _keys.press(e.character) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// In the filter: Esc, Enter or Tab go back to the list, arrow down also moves into it.
  KeyEventResult _filterKey(LogicalKeyboardKey k) {
    const back = [LogicalKeyboardKey.escape, LogicalKeyboardKey.enter, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.tab];
    if (!back.contains(k)) return KeyEventResult.ignored;
    focus.requestFocus();
    if (k == LogicalKeyboardKey.arrowDown) move(1);
    return KeyEventResult.handled;
  }

  void _tapRow(Object? key) {
    focus.requestFocus();
    browser.toggle(key);
  }

  // Layout ---------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onKeyEvent: onKey,
    child: ListenableBuilder(
      listenable: Listenable.merge([ws, browser, session.jobs]),
      builder: (context, _) {
        if (ws.loaded) return LayoutBuilder(builder: (context, box) => _layout(box.maxWidth));
        if (ws.error != null) return ErrorPane(ws.error!, onRetry: ws.load);
        return const Empty('Loading planning files…');
      },
    ),
  );

  Widget _layout(double width) {
    final rows = browser.rows();
    return Row(
      children: [
        SizedBox(width: 220, child: _nav()),
        const VerticalDivider(width: 1),
        Expanded(child: _list(rows)),
        DetailPanel(width: ((width - 221) * .45).clamp(360.0, 600.0), child: _detail()),
      ],
    );
  }

  Widget _nav() => TasksNav(
    browser: browser,
    projectName: ws.projectName,
    scope: ScopeInfo(
      source: ws.tracking?.elsewhere == true ? ws.tracking!.name : null,
      project: ws.project,
      projectOnly: ws.projectOnly,
      onToggle: toggleProjectOnly,
    ),
    loading: ws.loading,
    jobs: session.jobs.value.values.where((j) => j.running).toList(),
    onCancelJob: _cancelJob,
  );

  Widget _list(List<ListRow> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TaskListHeader(
        title: browser.title,
        count: rows.where((r) => !r.isHeader).length,
        filter: filter,
        filterFocus: filterFocus,
        onQuery: browser.setQuery,
        action: _viewAction(),
      ),
      Expanded(
        child: TaskRows(
          rows: rows,
          ws: ws,
          selected: browser.selected,
          scroll: scroll,
          headerIcons: browser.view == TView.changes || (browser.view == TView.tasks && browser.groupBy == 'status'),
          onTap: _tapRow,
        ),
      ),
    ],
  );

  /// The button at the end of the list header: depends on the view.
  Widget? _viewAction() => switch (browser.view) {
    TView.changes => SmallButton('New change', icon: Icons.auto_awesome, onPressed: newChange),
    TView.inbox => SmallButton('Mark all seen', icon: Icons.done_all, onPressed: markSeen),
    TView.tasks => GroupByMenu(value: browser.groupBy, options: TaskBrowser.groupings, onPick: browser.setGroupBy),
    _ => null,
  };

  /// The detail panel for the selection; null closes the panel.
  Widget? _detail() => switch (browser.selected) {
    null => null,
    final String id when ws.task(id) != null =>
      TaskDetail(key: ValueKey(ws.task(id)!.path), task: ws.task(id)!, ws: ws, actions: this),
    final ChangeKey k when _change(k) != null => ChangeDetail(change: _change(k)!, ws: ws, actions: this, onArchive: archive),
    final SpecKey k => _specDetail(k),
    final MilestoneKey k => MilestoneDetail(name: k.name, ws: ws, onClose: close, onChange: openChange),
    final LegacyKey k when ws.legacyAt(k) != null => _legacyDetail(ws.legacyAt(k)!),
    _ => const Empty('Gone: the file moved or was deleted.'),
  };

  Change? _change(ChangeKey k) => ws.changes.where((c) => c.dir == k.dir).firstOrNull;

  Widget _specDetail(SpecKey k) {
    final sp = ws.specs.where((x) => x.capability == k.capability).firstOrNull;
    final r = sp?.requirements.where((x) => x.name == k.requirement).firstOrNull;
    if (sp == null || r == null) return const Empty('Gone: the file moved or was deleted.');
    return SpecDetail(
      spec: sp,
      requirement: r,
      ws: ws,
      onClose: close,
      onChange: openChange,
      onOpen: () => openInNeovim(sp.doc.path, r.start + 1),
    );
  }

  Widget _legacyDetail(LegacyItem l) => LegacyDetail(
    item: l,
    onClose: close,
    onPromote: () => promote(l),
    onOpen: () => openInNeovim('legacy/${l.file}', l.line + 1),
    promotedAs: ws.promotedAs(l),
    onTask: openTask,
  );
}
