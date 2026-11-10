import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/prefs.dart';
import '../../tasks/inbox.dart';
import '../../tasks/markdown.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'change_detail.dart';
import 'detail_parts.dart';
import 'dialogs.dart';
import 'icons.dart';
import 'legacy_detail.dart';
import 'milestone_detail.dart';
import 'rich.dart';
import 'spec_detail.dart';
import 'task_detail.dart';

enum TView { inbox, tasks, changes, specs, legacy, milestones }

/// A row of the main list: a group header or an item that opens in the detail panel.
class ListRow {
  ListRow.header(this.title, this.count) : key = null, build = null;
  ListRow.item(this.key, this.build) : title = null, count = null;

  final String? title;
  final int? count;
  final Object? key; // what the detail panel shows
  final Widget Function(bool selected)? build;
  bool get isHeader => title != null;
}

/// The Tasks mode: a Linear-style workspace over the repo's OpenSpec and Backlog.md files.
class TasksView extends StatefulWidget {
  const TasksView({super.key, required this.ws, this.onReview});

  final Workspace ws;
  final void Function(Task task, String branch)? onReview;

  @override
  State<TasksView> createState() => TasksViewState();
}

class TasksViewState extends State<TasksView> implements TaskActions {
  TView view = TView.inbox;
  final prefs = Prefs.load();
  int? cursor; // index into the current items, so J/K work when an item shows up twice
  String? statusFilter = 'open'; // 'open', a status, or null for all
  String? labelFilter;
  String groupBy = 'status';
  String query = '';
  Object? selected; // Task id (String), ChangeKey or LegacyKey

  String get _repoKey => session.repo?.root ?? 'repo';

  /// When the inbox was last marked seen; the first visit of a repo counts as seen now.
  DateTime get lastSeen {
    final t = prefs.lastSeen(_repoKey);
    if (t != null) return t;
    final now = DateTime.now();
    prefs.setLastSeen(_repoKey, now);
    return now;
  }

  void markSeen() => setState(() => prefs.setLastSeen(_repoKey, DateTime.now()));

  LegacyItem? legacyAt(LegacyKey k) => ws.legacy.where((l) => l.file == k.file && l.line == k.line).firstOrNull;

  /// A task created from this legacy item (its original notes start with the item's line).
  String? promotedAs(LegacyItem l) =>
      ws.tasks.where((t) => t.originalNotes.isNotEmpty && t.originalNotes.first.contains(l.text)).firstOrNull?.id;

  Future<void> archive(Change c) async {
    final caps = {for (final d in c.deltas) d.capability};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Archive this change?', style: T.title),
        content: Text(
          [
            if (caps.isNotEmpty)
              'Its ${c.deltas.length} requirement changes go into the living spec (${caps.join(', ')}).',
            if (ws.taskFor(c) != null) '${ws.taskFor(c)!.id} is marked Done.',
            'The folder moves to openspec/changes/archive/.',
          ].join('\n'),
          style: T.body,
        ),
        actions: [
          SmallButton('Cancel', onPressed: () => Navigator.pop(d, false)),
          SmallButton('Archive', primary: true, onPressed: () => Navigator.pop(d, true)),
        ],
      ),
    );
    focus.requestFocus();
    if (ok != true) return;
    final err = await ws.archive(c);
    _snack(err);
    if (err == null && mounted) setState(() => selected = null);
  }

  /// Jobs this view started, waiting for their `finished` event.
  final _waiting = <int>{};
  Set<String> _changesBefore = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      session.jobs.addListener(_onJobs);
      ws.links.addAll(prefs.branchLinks(_repoKey));
    });
  }

  void _onJobs() {
    for (final id in [..._waiting]) {
      final j = session.jobs.value[id];
      if (j == null || j.running) continue;
      _waiting.remove(id);
      if (j.code == 0) {
        ws.load().then((_) {
          final fresh = ws.changes.where((c) => !_changesBefore.contains(c.dir)).toList();
          if (fresh.isNotEmpty && mounted) {
            setState(() {
              view = TView.changes;
              selected = ChangeKey(fresh.first.dir);
            });
          }
          _snack(fresh.isEmpty ? 'The agent finished but wrote no change.' : 'Drafted: ${fresh.first.title}');
        });
      } else {
        final why = (j.stderr.isNotEmpty ? j.stderr : j.stdout).trim().split('\n').last;
        _snack('The agent failed (${j.code}): $why');
      }
    }
  }

  Future<void> newChange() async {
    final sentence = await showDialog<String>(context: context, builder: (_) => const NewChangeDialog());
    focus.requestFocus();
    if (sentence == null || sentence.isEmpty) return;
    _changesBefore = {for (final c in ws.changes) c.dir};
    final (err, id) = await ws.newChange(sentence);
    if (err != null) return _snack(err);
    if (id != null) _waiting.add(id);
    _snack('An agent is drafting the change; it shows up here when done.');
    setState(() {});
  }

  Future<void> promote(LegacyItem l) => createTask(
    title: l.text.replaceAll(RegExp(r'\s*\(([0-9a-f]{7,10}(, )?)+\)'), '').replaceAll(RegExp(r';?\s*untested\s*$'), ''),
    labels: ['legacy', l.group],
    notes: ['- [${l.done ? 'x' : ' '}] ${l.text}', ...l.notes],
  );

  Workspace get ws => widget.ws;
  Session get session => SessionScope.read(context);

  void _snack(String? err) {
    if (err != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  // TaskActions -------------------------------------------------------------------------------

  @override
  void openTask(String id) {
    final t = ws.task(id);
    if (t == null) return _snack('$id not found');
    setState(() => selected = t.id);
  }

  @override
  void openChange(Change c) => setState(() => selected = ChangeKey(c.dir));

  @override
  void close() => setState(() => selected = null);

  @override
  void openInNeovim(String path, int line) async => _snack(await session.run((b) => b.open(path, line)));

  @override
  Future<void> setStatus(Task t, String status) async => _snack(await ws.setTaskStatus(t, status));

  @override
  Future<void> setPriority(Task t, String priority) async => _snack(await ws.setTaskPriority(t, priority));

  @override
  Future<void> toggleCheck(String path, Check c) async => _snack(await ws.toggleCheck(path, c));

  // Keyboard ----------------------------------------------------------------------------------

  final focus = FocusNode(debugLabel: 'tasks');
  final filterFocus = FocusNode(debugLabel: 'tasks filter');
  final filter = TextEditingController();
  final scroll = ScrollController();
  static const rowHeight = 36.0;

  @override
  void dispose() {
    session.jobs.removeListener(_onJobs);
    focus.dispose();
    filterFocus.dispose();
    filter.dispose();
    scroll.dispose();
    super.dispose();
  }

  Task? get selectedTask => selected is String ? ws.task(selected as String) : null;

  /// Move the selection by [delta] items (J/K), opening the item in the panel.
  void move(int delta) {
    final all = rows();
    final positions = [
      for (var i = 0; i < all.length; i++)
        if (!all[i].isHeader) i,
    ];
    if (positions.isEmpty) return;
    var i = cursor != null && cursor! < positions.length && all[positions[cursor!]].key == selected
        ? cursor!
        : positions.indexWhere((p) => all[p].key == selected);
    final next = i < 0 ? (delta > 0 ? 0 : positions.length - 1) : (i + delta).clamp(0, positions.length - 1);
    i = next;
    setState(() {
      cursor = next;
      selected = all[positions[next]].key;
    });
    final index = positions[next];
    if (scroll.hasClients && index >= 0) {
      final top = index * rowHeight, bottom = top + rowHeight;
      final view = scroll.position.viewportDimension, off = scroll.offset;
      if (top < off) scroll.jumpTo(top);
      if (bottom > off + view) scroll.jumpTo(bottom - view);
    }
  }

  void cycleStatus() {
    final t = selectedTask;
    if (t == null) return;
    final i = ws.statuses.indexOf(t.status);
    setStatus(t, ws.statuses[(i + 1) % ws.statuses.length]);
  }

  void cyclePriority() {
    final t = selectedTask;
    if (t == null) return;
    const order = ['', 'low', 'medium', 'high'];
    final i = order.indexOf(t.priority.toLowerCase());
    setPriority(t, order[(i + 1) % order.length]);
  }

  KeyEventResult onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (filterFocus.hasFocus) {
      if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.arrowDown) {
        focus.requestFocus();
        if (k == LogicalKeyboardKey.arrowDown) move(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (ctrl && k == LogicalKeyboardKey.keyK) {
      openPalette();
      return KeyEventResult.handled;
    }
    if (ctrl || HardwareKeyboard.instance.isAltPressed) return KeyEventResult.ignored;
    switch (k) {
      case LogicalKeyboardKey.keyJ || LogicalKeyboardKey.arrowDown:
        move(1);
      case LogicalKeyboardKey.keyK || LogicalKeyboardKey.arrowUp:
        move(-1);
      case LogicalKeyboardKey.enter:
        if (selected == null) move(1);
      case LogicalKeyboardKey.escape:
        if (selected != null) close();
      case LogicalKeyboardKey.slash:
        filterFocus.requestFocus();
      case LogicalKeyboardKey.keyC:
        createTask();
      case LogicalKeyboardKey.keyS:
        cycleStatus();
      case LogicalKeyboardKey.keyP:
        cyclePriority();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> createTask({String title = '', List<String> labels = const [], List<String> notes = const []}) async {
    final r = await showDialog<NewTask>(
      context: context,
      builder: (_) => NewTaskDialog(statuses: ws.statuses, title: title, labels: labels),
    );
    focus.requestFocus();
    if (r == null || r.title.trim().isEmpty) return;
    final (err, id) = await ws.createTask(
      title: r.title.trim(),
      status: r.status,
      labels: r.labels,
      description: r.description.isEmpty ? [] : r.description.split('\n'),
      originalNotes: notes,
    );
    _snack(err);
    if (err == null) {
      setState(() {
        view = TView.tasks;
        selected = id;
      });
    }
  }

  Future<void> openPalette() async {
    final entries = <PaletteEntry>[
      PaletteEntry('New task', 'C', Icons.add, createTask),
      PaletteEntry('New change (an agent drafts it)', 'agent', Icons.auto_awesome, newChange),
      PaletteEntry(
        'Open tasks',
        'view',
        Icons.inbox_outlined,
        () => setState(() {
          view = TView.tasks;
          statusFilter = 'open';
          labelFilter = null;
        }),
      ),
      for (final s in ws.statuses)
        PaletteEntry(
          s,
          'view',
          Icons.circle_outlined,
          () => setState(() {
            view = TView.tasks;
            statusFilter = s;
            labelFilter = null;
          }),
        ),
      PaletteEntry('Changes', 'view', Icons.description_outlined, () => setState(() => view = TView.changes)),
      if (selectedTask != null)
        for (final s in ws.statuses)
          PaletteEntry('Set status: $s', selectedTask!.id, Icons.flag_outlined, () => setStatus(selectedTask!, s)),
      if (selectedTask != null)
        PaletteEntry(
          'Open ${selectedTask!.id} in Neovim',
          'file',
          Icons.open_in_new,
          () => openInNeovim(selectedTask!.path, 1),
        ),
      for (final t in ws.tasks) PaletteEntry('${t.id}  ${t.title}', t.status, Icons.task_alt, () => openTask(t.id)),
      for (final c in ws.changes.where((c) => !c.archived))
        PaletteEntry(c.title, 'change', Icons.description_outlined, () => openChange(c)),
    ];
    final picked = await showDialog<PaletteEntry>(context: context, builder: (_) => Palette(entries));
    focus.requestFocus();
    picked?.run();
  }

  @override
  Future<void> review(Task t, String branch) async => widget.onReview?.call(t, branch);

  @override
  Future<void> linkBranch(Task t, String? branch) async {
    await ws.linkBranch(t, branch);
    prefs.setBranchLinks(_repoKey, Map.of(ws.links));
  }

  // Rows --------------------------------------------------------------------------------------

  bool _matches(String text) => query.isEmpty || text.toLowerCase().contains(query.toLowerCase());

  List<Task> get visibleTasks => ws.tasks.where((t) {
    if (labelFilter != null && !t.labels.contains(labelFilter)) return false;
    if (statusFilter == 'open' && (t.status == 'Done' || t.status == 'Dropped' || t.archived)) return false;
    if (statusFilter != null && statusFilter != 'open' && t.status != statusFilter) return false;
    return _matches('${t.id} ${t.title} ${t.labels.join(' ')}');
  }).toList();

  List<ListRow> rows() {
    switch (view) {
      case TView.inbox:
        final items = inbox(ws, lastSeen)
            .where((i) => _matches('${i.task?.title ?? ''} ${i.change?.title ?? ''} ${i.legacy?.text ?? ''} ${i.why}'))
            .toList();
        return [
          for (final section in [sinceSection, ...attentionSections])
            if (items.any((i) => i.section == section)) ...[
              ListRow.header(section, items.where((i) => i.section == section).length),
              for (final i in items.where((i) => i.section == section))
                ListRow.item(
                  i.task?.id ??
                      (i.change != null
                          ? ChangeKey(i.change!.dir)
                          : (i.legacy != null ? LegacyKey(i.legacy!.file, i.legacy!.line) : i.branch?.name)),
                  (sel) => _InboxRow(i),
                ),
            ],
        ];
      case TView.tasks:
        final tasks = visibleTasks;
        final groups = <String, List<Task>>{};
        List<String> order;
        if (groupBy == 'priority') {
          order = ['high', 'medium', 'low', ''];
          for (final t in tasks) {
            groups.putIfAbsent(t.priority.toLowerCase(), () => []).add(t);
          }
        } else if (groupBy == 'label') {
          for (final t in tasks) {
            for (final l in t.labels.isEmpty ? [''] : t.labels) {
              groups.putIfAbsent(l, () => []).add(t);
            }
          }
          order = groups.keys.toList()..sort();
        } else {
          order = ws.statuses;
          for (final t in tasks) {
            groups.putIfAbsent(t.status, () => []).add(t);
          }
        }
        return [
          for (final g in order)
            if (groups[g]?.isNotEmpty ?? false) ...[
              ListRow.header(g.isEmpty ? (groupBy == 'priority' ? 'No priority' : 'No label') : g, groups[g]!.length),
              for (final t in groups[g]!) ListRow.item(t.id, (sel) => _TaskRow(t, ws, sel)),
            ],
        ];
      case TView.legacy:
        final items = ws.legacy
            .where((l) => _matches('${l.file} ${l.section} ${l.text} ${l.notes.join(' ')}'))
            .toList();
        final groups = <String>[];
        for (final l in items) {
          if (!groups.contains(l.group)) groups.add(l.group);
        }
        // Years first, newest on top; then the other notes files by name.
        bool year(String g) => RegExp(r'^\d{4}$').hasMatch(g);
        groups.sort((a, b) => year(a) != year(b) ? (year(a) ? -1 : 1) : (year(a) ? b.compareTo(a) : a.compareTo(b)));
        return [
          for (final g in groups) ...[
            ListRow.header(g, items.where((l) => l.group == g).length),
            for (final l in items.where((l) => l.group == g))
              ListRow.item(LegacyKey(l.file, l.line), (sel) => _LegacyRow(l, promotedAs(l))),
          ],
        ];
      case TView.milestones:
        final names = [openMilestone, ...ws.milestones.reversed.map((m) => m.name)];
        return [
          ListRow.header(ws.milestonesFromFile ? 'milestones.md' : 'By month of archiving', names.length),
          for (final n in names.where((n) => _matches(n))) ListRow.item(MilestoneKey(n), (sel) => _MilestoneRow(n, ws)),
        ];
      case TView.specs:
        return [
          for (final sp in ws.specs)
            if (sp.requirements.any((r) => _matches('${sp.capability} ${r.name} ${r.text}'))) ...[
              ListRow.header(sp.capability, sp.requirements.length),
              for (final r in sp.requirements.where((r) => _matches('${sp.capability} ${r.name} ${r.text}')))
                ListRow.item(SpecKey(sp.capability, r.name), (sel) => _SpecRow(r, ws)),
            ],
        ];
      case TView.changes:
        final list = ws.changes.where((c) => _matches('${c.id} ${c.title}')).toList();
        return [
          for (final stage in ['Active', 'Draft', 'Completed'])
            if (list.any((c) => c.stage == stage)) ...[
              ListRow.header(stage, list.where((c) => c.stage == stage).length),
              for (final c in list.where((c) => c.stage == stage))
                ListRow.item(ChangeKey(c.dir), (sel) => _ChangeRow(c, ws, sel)),
            ],
        ];
    }
  }

  String get title {
    if (view == TView.inbox) return 'Inbox';
    if (view == TView.changes) return 'Changes';
    if (view == TView.specs) return 'Specs';
    if (view == TView.legacy) return 'Legacy notes';
    if (view == TView.milestones) return 'Milestones';
    if (labelFilter != null) return labelFilter!;
    return switch (statusFilter) {
      'open' => 'Open tasks',
      null => 'All tasks',
      final s => s,
    };
  }

  // Build -------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: onKey,
      child: ListenableBuilder(
        listenable: ws,
        builder: (context, _) {
          if (!ws.loaded) return Empty(ws.error ?? 'Loading planning files…');
          final rs = rows();
          return LayoutBuilder(
            builder: (context, box) {
              final panel = ((box.maxWidth - 221) * .45).clamp(360.0, 600.0);
              return Row(
                children: [
                  SizedBox(width: 220, child: _sidebar()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _list(rs)),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: selected == null ? 0 : panel,
                    decoration: const BoxDecoration(
                      color: C.surface,
                      border: Border(left: BorderSide(color: C.border)),
                    ),
                    child: selected == null
                        ? const SizedBox.shrink()
                        : ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: panel,
                              maxWidth: panel,
                              child: _detail(),
                            ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _detail() {
    final sel = selected;
    if (sel is String) {
      final t = ws.task(sel);
      if (t != null) return TaskDetail(key: ValueKey(t.path), task: t, ws: ws, actions: this);
    }
    if (sel is ChangeKey) {
      final c = ws.changes.where((c) => c.dir == sel.dir).firstOrNull;
      if (c != null) return ChangeDetail(change: c, ws: ws, actions: this, onArchive: archive);
    }
    if (sel is SpecKey) {
      final sp = ws.specs.where((x) => x.capability == sel.capability).firstOrNull;
      final r = sp?.requirements.where((x) => x.name == sel.requirement).firstOrNull;
      if (sp != null && r != null) {
        return SpecDetail(
          spec: sp,
          requirement: r,
          ws: ws,
          onClose: close,
          onChange: openChange,
          onOpen: () => openInNeovim(sp.doc.path, r.start + 1),
        );
      }
    }
    if (sel is MilestoneKey) {
      return MilestoneDetail(name: sel.name, ws: ws, onClose: close, onChange: openChange);
    }
    if (sel is LegacyKey) {
      final l = legacyAt(sel);
      if (l != null) {
        return LegacyDetail(
          item: l,
          onClose: close,
          onPromote: () => promote(l),
          onOpen: () => openInNeovim('legacy/${l.file}', l.line + 1),
          promotedAs: promotedAs(l),
          onTask: openTask,
        );
      }
    }
    return const Empty('Gone: the file moved or was deleted.');
  }

  Widget _sidebar() {
    int count(bool Function(Task) f) => ws.tasks.where(f).length;
    Widget item(String label, IconData icon, bool sel, VoidCallback onTap, {int? n, Widget? lead}) => HoverRow(
      selected: sel,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          lead ?? Icon(icon, size: 15, color: sel ? C.text : C.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: T.body.copyWith(color: sel ? C.text : const Color(0xFFC8CBD3)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (n != null) Text('$n', style: T.tiny),
        ],
      ),
    );
    bool isTasks(String? status) => view == TView.tasks && labelFilter == null && statusFilter == status;
    void showTasks(String? status, {String? label}) => setState(() {
      view = TView.tasks;
      statusFilter = status;
      labelFilter = label;
    });
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 12, 12),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(5)),
                child: Text(
                  ws.projectName.isEmpty ? 'F' : ws.projectName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.bg),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  ws.projectName.isEmpty ? 'Folio' : ws.projectName,
                  style: T.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (ws.loading) const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
            ],
          ),
        ),
        for (final j in session.jobs.value.values.where((j) => j.running))
          Tooltip(
            message: '${j.label}\nclick to cancel',
            child: HoverRow(
              onTap: () => session.run((b) => b.cancelJob(j.id)),
              padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
              child: Row(
                children: [
                  const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Agent: ${j.label}', style: T.small, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        item(
          'Inbox',
          Icons.notifications_none,
          view == TView.inbox,
          () => setState(() => view = TView.inbox),
          n: inbox(ws, lastSeen).length,
        ),
        const SizedBox(height: 8),
        item(
          'Open tasks',
          Icons.task_alt,
          isTasks('open'),
          () => showTasks('open'),
          n: count((t) => !t.archived && t.status != 'Done' && t.status != 'Dropped'),
        ),
        for (final s in ws.statuses)
          item(
            s,
            Icons.circle,
            isTasks(s),
            () => showTasks(s),
            n: count((t) => t.status == s),
            lead: StatusIcon(s, size: 13),
          ),
        item('All tasks', Icons.list, isTasks(null), () => showTasks(null), n: ws.tasks.length),
        const SizedBox(height: 10),
        item(
          'Changes',
          Icons.description_outlined,
          view == TView.changes,
          () => setState(() => view = TView.changes),
          n: ws.changes.where((c) => !c.archived).length,
        ),
        item(
          'Specs',
          Icons.account_tree_outlined,
          view == TView.specs,
          () => setState(() => view = TView.specs),
          n: ws.specs.fold<int>(0, (n, s) => n + s.requirements.length),
        ),
        item(
          'Milestones',
          Icons.flag_outlined,
          view == TView.milestones,
          () => setState(() => view = TView.milestones),
          n: ws.milestones.length + 1,
        ),
        item(
          'Legacy notes',
          Icons.history,
          view == TView.legacy,
          () => setState(() => view = TView.legacy),
          n: ws.legacy.length,
        ),
        if (ws.labels.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 16, 12, 6),
            child: Text('LABELS', style: T.section),
          ),
          for (final l in ws.labels)
            item(
              l,
              Icons.label_outline,
              view == TView.tasks && labelFilter == l,
              () => showTasks(null, label: l),
              n: count((t) => t.labels.contains(l)),
            ),
        ],
      ],
    );
  }

  Widget _list(List<ListRow> rs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.border)),
          ),
          child: Row(
            children: [
              Flexible(
                child: Text(title, style: T.title, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('${rs.where((r) => !r.isHeader).length}', style: T.tiny),
              const Spacer(),
              Flexible(
                flex: 4,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220, maxHeight: 28),
                  child: TextField(
                    controller: filter,
                    focusNode: filterFocus,
                    style: T.body,
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'Filter  /',
                      prefixIcon: Icon(Icons.search, size: 15, color: C.muted),
                      prefixIconConstraints: BoxConstraints(minWidth: 30),
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                ),
              ),
              if (view == TView.changes) ...[
                const SizedBox(width: 10),
                SmallButton('New change', icon: Icons.auto_awesome, onPressed: newChange),
              ],
              if (view == TView.inbox) ...[
                const SizedBox(width: 10),
                SmallButton('Mark all seen', icon: Icons.done_all, onPressed: markSeen),
              ],
              if (view == TView.tasks) ...[
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  tooltip: 'Group by',
                  color: C.surface2,
                  onSelected: (g) => setState(() => groupBy = g),
                  itemBuilder: (_) => [
                    for (final g in ['status', 'priority', 'label'])
                      PopupMenuItem(
                        value: g,
                        height: 32,
                        child: Text('Group by $g', style: T.body),
                      ),
                  ],
                  child: Row(
                    children: [
                      const Icon(Icons.view_agenda_outlined, size: 15, color: C.muted),
                      const SizedBox(width: 5),
                      Text(groupBy, style: T.small),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: rs.isEmpty
              ? const Empty('Nothing here.')
              : ListView.builder(
                  controller: scroll,
                  itemExtent: rowHeight,
                  itemCount: rs.length,
                  itemBuilder: (context, i) {
                    final r = rs[i];
                    if (r.isHeader) {
                      return Container(
                        color: C.surface,
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                        child: Row(
                          children: [
                            if (view == TView.tasks && groupBy == 'status') ...[
                              StatusIcon(r.title!, size: 13),
                              const SizedBox(width: 8),
                            ],
                            if (view == TView.changes) ...[StatusIcon(r.title!, size: 13), const SizedBox(width: 8)],
                            Text(r.title!, style: T.body.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Text('${r.count}', style: T.tiny),
                          ],
                        ),
                      );
                    }
                    final sel = r.key == selected;
                    return HoverRow(
                      selected: sel,
                      onTap: () {
                        focus.requestFocus();
                        setState(() => selected = sel ? null : r.key);
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                      child: SizedBox(height: 36, child: r.build!(sel)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Identifies a change in the selection.
class ChangeKey {
  const ChangeKey(this.dir);
  final String dir;
  @override
  bool operator ==(Object other) => other is ChangeKey && other.dir == dir;
  @override
  int get hashCode => dir.hashCode;
}

class _TaskRow extends StatelessWidget {
  const _TaskRow(this.t, this.ws, this.selected);

  final Task t;
  final Workspace ws;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final checks = [...t.acceptance, ...t.verify];
    final change = ws.changeFor(t);
    final branch = ws.branchFor(t);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 640, medium = box.maxWidth > 420;
        return Row(
          children: [
            PriorityIcon(t.priority),
            const SizedBox(width: 10),
            SizedBox(
              width: 62,
              child: Text(
                t.id,
                style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.faint),
              ),
            ),
            StatusIcon(t.status),
            const SizedBox(width: 10),
            Expanded(child: RichLine(t.title, maxLines: 1)),
            if (branch != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: branch,
                child: const Icon(Icons.call_split, size: 14, color: C.green),
              ),
            ],
            if (change != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: change.title,
                child: Icon(Icons.description_outlined, size: 14, color: statusColor(change.stage)),
              ),
            ],
            if (wide)
              for (final l in t.labels.take(2)) ...[const SizedBox(width: 6), labelPill(l)],
            if (medium && checks.isNotEmpty) ...[
              const SizedBox(width: 10),
              Progress(checks.where((c) => c.done).length, checks.length, width: 30),
            ],
          ],
        );
      },
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow(this.c, this.ws, this.selected);

  final Change c;
  final Workspace ws;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final checks = c.allChecks;
    final t = ws.taskFor(c);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 560;
        return Row(
          children: [
            StatusIcon(c.stage),
            const SizedBox(width: 10),
            Expanded(child: RichLine(c.title, maxLines: 1)),
            if (c.deltas.isNotEmpty) ...[const SizedBox(width: 8), Pill('${c.deltas.length} req', color: C.purple)],
            if (wide && t != null) ...[
              const SizedBox(width: 8),
              Text(
                t.id,
                style: const TextStyle(fontSize: 11, fontFamily: mono, color: C.faint),
              ),
            ],
            if (wide && c.archiveDate != null) ...[
              const SizedBox(width: 8),
              Text(
                '${c.archiveDate!.year}-${c.archiveDate!.month.toString().padLeft(2, '0')}-${c.archiveDate!.day.toString().padLeft(2, '0')}',
                style: T.tiny,
              ),
            ],
            if (wide && checks.isNotEmpty) ...[
              const SizedBox(width: 10),
              Progress(checks.where((x) => x.done).length, checks.length, width: 30),
            ],
          ],
        );
      },
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow(this.i);

  final InboxItem i;

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String id, String title) = switch (i) {
      InboxItem(task: final t?) => (StatusIcon(t.status), t.id, t.title),
      InboxItem(change: final c?) => (StatusIcon(c.stage), 'change', c.title),
      InboxItem(legacy: final l?) => (const Icon(Icons.history, size: 15, color: C.yellow), l.group, l.text),
      InboxItem(branch: final b?) => (const Icon(Icons.call_split, size: 15, color: C.green), 'branch', b.subject),
      _ => (const SizedBox(width: 14), '', ''),
    };
    return Row(
      children: [
        icon,
        const SizedBox(width: 10),
        SizedBox(
          width: 62,
          child: Text(
            id,
            style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.faint),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(child: RichLine(title, maxLines: 1)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(i.why, style: T.tiny, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow(this.r, this.ws);

  final Requirement r;
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final n = ws.changesTouching(r.name).length;
    return Row(
      children: [
        const Icon(Icons.rule, size: 15, color: C.muted),
        const SizedBox(width: 10),
        Expanded(child: RichLine(r.name, maxLines: 1)),
        if (r.scenarios.isNotEmpty) ...[
          Text('${r.scenarios.length} scenario${r.scenarios.length == 1 ? '' : 's'}', style: T.tiny),
          const SizedBox(width: 10),
        ],
        if (n > 0) Text('$n change${n == 1 ? '' : 's'}', style: T.tiny),
      ],
    );
  }
}

class _LegacyRow extends StatelessWidget {
  const _LegacyRow(this.l, this.promoted);

  final LegacyItem l;
  final String? promoted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          Icon(
            l.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            size: 15,
            color: l.done ? C.faint : C.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichLine(l.text, maxLines: 1, style: T.body.copyWith(color: l.done ? C.muted : C.text)),
          ),
          if (l.untested) ...[const SizedBox(width: 8), const Pill('untested', color: C.yellow)],
          if (promoted != null) ...[
            const SizedBox(width: 8),
            Text(
              promoted!,
              style: const TextStyle(fontSize: 11, fontFamily: mono, color: C.accent),
            ),
          ],
          if (box.maxWidth > 560) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 160,
              child: Text(l.section, style: T.tiny, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
            ),
          ],
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow(this.name, this.ws);

  final String name;
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final list = milestoneChanges(ws, name);
    final m = ws.milestones.where((m) => m.name == name).firstOrNull;
    return Row(
      children: [
        Icon(
          name == openMilestone ? Icons.outlined_flag : Icons.flag,
          size: 15,
          color: name == openMilestone ? C.yellow : C.accent,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: T.body)),
        if (m?.date != null) ...[Text(fmtDate(m!.date!), style: T.tiny), const SizedBox(width: 12)],
        Text('${list.length} changes', style: T.tiny),
        const SizedBox(width: 10),
        Progress(list.where((c) => c.stage == 'Completed').length, list.length, width: 50),
      ],
    );
  }
}
