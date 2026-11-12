import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../backend/models.dart';
import '../../state/nvim_launcher.dart';
import '../../state/prefs.dart';
import '../../state/session.dart';
import '../../tasks/auto_status.dart';
import '../../tasks/browser.dart';
import '../../tasks/markdown.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../error_view.dart';
import '../key_sequence.dart';
import '../nav_keys.dart';
import '../widgets.dart';
import 'change_detail.dart';
import 'detail_parts.dart';
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
/// The panes of the Tasks mode the arrow keys move between: the sidebar, the task list and the
/// detail of the current task (where the keys move from element to element, not by lines).
enum TasksPane { nav, list, detail }

class TasksView extends StatefulWidget {
  const TasksView({super.key, required this.ws, this.onReview, this.onRail});

  /// Gives the keyboard to the mode rail (Left, Tab round the cycle).
  final VoidCallback? onRail;

  final Workspace ws;
  final void Function(Task task, String branch)? onReview;

  @override
  State<TasksView> createState() => TasksViewState();
}

class TasksViewState extends State<TasksView> implements TaskActions {
  final prefs = Prefs.load();
  late final browser = TaskBrowser(widget.ws, lastSeen: lastSeen);
  Session? _session;

  /// Where the up / down keys act: the sidebar's entries or the task list.
  TasksPane pane = TasksPane.list;

  void _goPane(TasksPane p) {
    setState(() => pane = p);
    focus.requestFocus();
  }

  /// Left: from the detail to the list, from the list to the sidebar, from the sidebar to the rail.
  void _left() => switch (pane) {
    TasksPane.detail => _goPane(TasksPane.list),
    TasksPane.list => _goPane(TasksPane.nav),
    TasksPane.nav => _toRail(),
  };

  /// Right: from the sidebar to the list, from the list to the detail of the current task.
  void _right() {
    if (pane == TasksPane.nav) {
      _goPane(TasksPane.list);
    } else if (pane == TasksPane.list) {
      _enterDetail();
    }
  }

  void _navigate(NavKey k) {
    switch (k.dir) {
      case NavDir.up || NavDir.down:
        _step(k.delta);
      case NavDir.left:
        _left();
      case NavDir.right:
        _right();
    }
  }

  // The detail pane ------------------------------------------------------------------------------

  /// The elements of the detail that take the keyboard (buttons, fields, rows), in tree order.
  final _detailScope = FocusScopeNode(debugLabel: 'task detail');

  List<FocusNode> _detailElements() => _detailScope.traversalDescendants.where((n) => n.canRequestFocus).toList();

  /// Right from the list: the keyboard goes to the first (with [last]: last) element of the current
  /// task's detail. With no element to take it, the pane is still active.
  void _enterDetail({bool last = false}) {
    if (browser.selected == null) move(1); // nothing is current yet: the first task
    if (browser.selected == null) return;
    setState(() => pane = TasksPane.detail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final els = _detailElements();
      els.isEmpty ? focus.requestFocus() : (last ? els.last : els.first).requestFocus();
    });
  }

  /// Keys while the detail has the keyboard: the direction keys move to the neighbouring element
  /// (Left past the first one goes back to the list); Tab goes through the elements in order, and
  /// on from the last one to the rail; Esc closes the detail. Enter and Space belong to the element.
  KeyEventResult _detailKey(KeyEvent e) {
    final primary = FocusManager.instance.primaryFocus;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      close();
      _goPane(TasksPane.list);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab) {
      final els = _detailElements();
      final i = primary == null ? -1 : els.indexOf(primary);
      if (HardwareKeyboard.instance.isShiftPressed) {
        i > 0 ? els[i - 1].requestFocus() : _goPane(TasksPane.list);
      } else {
        i + 1 < els.length ? els[i + 1].requestFocus() : (i < 0 && els.isNotEmpty ? els.first.requestFocus() : _toRail());
      }
      return KeyEventResult.handled;
    }
    final typing = primary?.context?.widget is EditableText || primary?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    final nav = typing ? null : navKey(e);
    if (nav == null) return KeyEventResult.ignored;
    final moved = primary?.focusInDirection(switch (nav.dir) {
      NavDir.up => TraversalDirection.up,
      NavDir.down => TraversalDirection.down,
      NavDir.left => TraversalDirection.left,
      NavDir.right => TraversalDirection.right,
    });
    if (moved != true && nav.dir == NavDir.left) _goPane(TasksPane.list);
    return KeyEventResult.handled;
  }

  /// Up / Down and friends: the next sidebar entry or task, whichever pane has the keys.
  void _step(int delta) => pane == TasksPane.nav ? browser.moveNav(delta) : move(delta);

  /// Ctrl+arrow, sent by the shell: only Left and Right go anywhere here.
  void ctrlArrow({required bool vertical, required int dir}) {
    if (vertical) return;
    dir < 0 ? _left() : _right();
  }

  final focus = FocusNode(debugLabel: 'tasks');
  final filterFocus = FocusNode(debugLabel: 'tasks filter');
  final filter = TextEditingController();
  final scroll = ScrollController();
  late final _keys = KeySequence({
    '{': () => _step(-3),
    '}': () => _step(3),
    'gg': () => _step(-1 << 20),
    'G': () => _step(1 << 20),
    'o': _openSelectedInNeovim,
  });

  /// Jobs this view started, waiting for their `finished` event.
  final _waiting = <int>{};
  Set<String> _changesBefore = {};

  Workspace get ws => widget.ws;

  /// The detail panel is twice as wide, over the list.
  bool wide = false;

  @override
  PanelWiden get widen => PanelWiden(wide: wide, onToggle: toggleWide);

  void toggleWide() => setState(() => wide = !wide);
  Session get session => _session!;
  Object? get selected => browser.selected;
  String get _repoKey => session.repo?.root ?? 'repo';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    _session = SessionScope.read(context);
    session.jobs.addListener(_onJobs);
    ws.autoStatus.addListener(_onAutoStatus);
    ws.links.addAll(prefs.branchLinks(_repoKey));
  }

  /// A tick moved a task on by itself: say so, with Undo.
  void _onAutoStatus() {
    final a = ws.autoStatus.value;
    if (a == null || !mounted) return;
    showAutoStatus(context, '${a.taskId} is ${a.to} now (all boxes ticked)', onUndo: () => _undoAutoStatus(a));
  }

  Future<void> _undoAutoStatus(AutoStatus a) async => _snack(await ws.undoAutoStatus(a));

  @override
  void dispose() {
    _session?.jobs.removeListener(_onJobs);
    ws.autoStatus.removeListener(_onAutoStatus);
    _keys.dispose();
    browser.dispose();
    _detailScope.dispose();
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

  void _toRail() => widget.onRail?.call();

  /// Tab from the rail: the sidebar; Shift+Tab from the rail: the list.
  void enterFromRail({required bool forward}) {
    if (forward) return _goPane(TasksPane.nav);
    browser.selected == null ? _goPane(TasksPane.list) : _enterDetail(last: true);
  }

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
    if (pane == TasksPane.detail && browser.selected == null) pane = TasksPane.list;
    if (pane == TasksPane.detail && !hw.isControlPressed && !hw.isAltPressed && !hw.isMetaPressed) {
      return _detailKey(e);
    }
    final action = switch (e.logicalKey) {
      LogicalKeyboardKey.keyK when hw.isControlPressed => openPalette,
      LogicalKeyboardKey.keyD when hw.isControlPressed => () => _page(1),
      LogicalKeyboardKey.keyU when hw.isControlPressed => () => _page(-1),
      _ when hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed => null,
      LogicalKeyboardKey.enter when pane == TasksPane.nav => _right,
      LogicalKeyboardKey.enter when browser.selected == null => () => move(1),
      LogicalKeyboardKey.escape when browser.selected != null => close,
      LogicalKeyboardKey.slash => filterFocus.requestFocus,
      // Tab goes round: rail, sidebar, filter, list, rail.
      LogicalKeyboardKey.tab => (pane == TasksPane.nav) != hw.isShiftPressed
          ? filterFocus.requestFocus
          : (pane == TasksPane.list && !hw.isShiftPressed && browser.selected != null ? _enterDetail : _toRail),
      LogicalKeyboardKey.keyC => createTask,
      LogicalKeyboardKey.keyT => cycleStatus,
      LogicalKeyboardKey.keyP => cyclePriority,
      LogicalKeyboardKey.keyA when ws.project != null && hw.isShiftPressed => toggleProjectOnly,
      _ => null,
    };
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    // The arrows, hjkl and wasd are one set of keys (see nav_keys.dart); a pending `g` owns the next key.
    final nav = _keys.pending ? null : navKey(e);
    if (nav != null) {
      _navigate(nav);
      return KeyEventResult.handled;
    }
    return _keys.press(e.character) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// In the filter: Esc, Enter or Tab go back to the list, arrow down also moves into it.
  KeyEventResult _filterKey(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.tab && HardwareKeyboard.instance.isShiftPressed) {
      _goPane(TasksPane.nav);
      return KeyEventResult.handled;
    }
    // Left moves the text cursor, except at the leftmost edge (or in an empty field): the rail.
    if (k == LogicalKeyboardKey.arrowLeft && !HardwareKeyboard.instance.isShiftPressed && cursorAtStart(filter)) {
      _goPane(TasksPane.nav);
      return KeyEventResult.handled;
    }
    const back = [LogicalKeyboardKey.escape, LogicalKeyboardKey.enter, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.tab];
    if (!back.contains(k)) return KeyEventResult.ignored;
    _goPane(TasksPane.list);
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
        Expanded(child: _listAndDetail(rows, width - 221)),
      ],
    );
  }

  /// The list, and the detail panel at its right; wide, the panel is twice as wide and covers the
  /// list instead of squeezing it.
  Widget _listAndDetail(List<ListRow> rows, double area) {
    final detail = _detail();
    final normal = (area * .45).clamp(360.0, 600.0);
    final panel = wide ? (normal * 2).clamp(normal, area) : normal;
    return Stack(
      children: [
        Positioned.fill(right: detail == null ? 0 : normal, child: _list(rows)),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: DetailPanel(
            width: panel,
            active: pane == TasksPane.detail,
            child: detail == null ? null : FocusScope(node: _detailScope, child: detail),
          ),
        ),
      ],
    );
  }

  Widget _nav() => TasksNav(
    active: pane == TasksPane.nav,
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
    final MilestoneKey k => MilestoneDetail(name: k.name, ws: ws, onClose: close, onChange: openChange, widen: widen),
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
      widen: widen,
      onChange: openChange,
      onOpen: () => openInNeovim(sp.doc.path, r.start + 1),
    );
  }

  Widget _legacyDetail(LegacyItem l) => LegacyDetail(
    item: l,
    onClose: close,
    widen: widen,
    onPromote: () => promote(l),
    onOpen: () => openInNeovim('legacy/${l.file}', l.line + 1),
    promotedAs: ws.promotedAs(l),
    onTask: openTask,
  );
}
