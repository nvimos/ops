import 'package:flutter/foundation.dart';

import 'inbox.dart';
import 'milestones.dart';
import 'model.dart';
import 'workspace.dart';

export 'milestones.dart' show openMilestone;

/// What the Tasks mode's main list shows.
enum TView { inbox, tasks, changes, specs, legacy, milestones }

// Selection keys: what the detail panel shows. A task is selected by its id (String).

class ChangeKey {
  const ChangeKey(this.dir);
  final String dir;
  @override
  bool operator ==(Object other) => other is ChangeKey && other.dir == dir;
  @override
  int get hashCode => dir.hashCode;
}

class LegacyKey {
  const LegacyKey(this.file, this.line);
  final String file;
  final int line;
  @override
  bool operator ==(Object other) => other is LegacyKey && other.file == file && other.line == line;
  @override
  int get hashCode => Object.hash(file, line);
}

class SpecKey {
  const SpecKey(this.capability, this.requirement);
  final String capability, requirement;
  @override
  bool operator ==(Object other) => other is SpecKey && other.capability == capability && other.requirement == requirement;
  @override
  int get hashCode => Object.hash(capability, requirement);
}

/// A milestone ('Next' is the open one).
class MilestoneKey {
  const MilestoneKey(this.name);
  final String name;
  @override
  bool operator ==(Object other) => other is MilestoneKey && other.name == name;
  @override
  int get hashCode => name.hashCode;
}


/// Changes of a milestone (see `planMilestones`): open ones first, then archived, newest first.
List<Change> milestoneChanges(Workspace ws, String name) =>
    ws.changesOf(name)..sort((a, b) => (b.archiveDate ?? DateTime(9999)).compareTo(a.archiveDate ?? DateTime(9999)));

String fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

extension LegacyLookup on Workspace {
  LegacyItem? legacyAt(LegacyKey k) => legacy.where((l) => l.file == k.file && l.line == k.line).firstOrNull;

  /// A task created from this legacy item (its original notes start with the item's line).
  String? promotedAs(LegacyItem l) =>
      tasks.where((t) => t.originalNotes.isNotEmpty && t.originalNotes.first.contains(l.text)).firstOrNull?.id;

  /// What archiving [c] will do, one line each, for the confirmation.
  List<String> archiveLines(Change c) {
    final caps = {for (final d in c.deltas) d.capability};
    final t = taskFor(c);
    return [
      if (caps.isNotEmpty) 'Its ${c.deltas.length} requirement changes go into the living spec (${caps.join(', ')}).',
      if (t != null) '${t.id} is marked Done.',
      'The folder moves to openspec/changes/archive/.',
    ];
  }
}

/// A new task's fields drafted from a legacy note: the text without commit hashes and
/// "untested", labelled legacy and its group, the note kept as original notes.
({String title, List<String> labels, List<String> notes}) promoteDraft(LegacyItem l) => (
  title: l.text.replaceAll(RegExp(r'\s*\(([0-9a-f]{7,10}(, )?)+\)'), '').replaceAll(RegExp(r';?\s*untested\s*$'), ''),
  labels: ['legacy', l.group],
  notes: ['- [${l.done ? 'x' : ' '}] ${l.text}', ...l.notes],
);

/// A row of the main list: a group header, or an item with its selection key and what it shows
/// (a Task, Change, InboxItem, LegacyItem, Requirement or milestone name).
class ListRow {
  ListRow.header(String this.title, int this.count) : key = null, data = null;
  ListRow.item(this.key, Object this.data) : title = null, count = null;

  final String? title;
  final int? count;
  final Object? key;
  final Object? data;
  bool get isHeader => title != null;
}

/// A sidebar entry: a view, a status filter or a label filter, with its count.
class NavTarget {
  const NavTarget(this.label, this.view, {this.status, this.byLabel, this.count = 0});

  final String label;
  final TView view;

  /// For [TView.tasks]: 'open', a status, or null for all.
  final String? status;

  /// For [TView.tasks]: a label filter.
  final String? byLabel;
  final int count;
}

/// What the Tasks mode shows: view, filters, grouping, the rows, the selection and J/K movement.
class TaskBrowser extends ChangeNotifier {
  TaskBrowser(this.ws, {required this.lastSeen});

  final Workspace ws;

  /// When the inbox was last marked seen.
  final DateTime Function() lastSeen;

  TView view = TView.inbox;
  String? statusFilter = 'open'; // 'open', a status, or null for all
  String? labelFilter;
  String groupBy = 'status';
  String query = '';
  Object? selected; // Task id (String), ChangeKey, LegacyKey, SpecKey or MilestoneKey
  int? cursor; // index into the current items, so J/K work when an item shows up twice

  static const groupings = ['status', 'priority', 'label'];

  Task? get selectedTask => selected is String ? ws.task(selected as String) : null;

  // Navigation -----------------------------------------------------------------------------------

  List<NavTarget> navTasks() {
    int count(bool Function(Task) f) => ws.tasks.where(f).length;
    return [
      NavTarget('Open tasks', TView.tasks, status: 'open', count: count(isOpen)),
      for (final s in ws.statuses) NavTarget(s, TView.tasks, status: s, count: count((t) => t.status == s)),
      NavTarget('All tasks', TView.tasks, count: ws.tasks.length),
    ];
  }

  List<NavTarget> navSources() => [
    NavTarget('Changes', TView.changes, count: ws.changes.where((c) => !c.archived).length),
    NavTarget('Specs', TView.specs, count: ws.specs.fold<int>(0, (n, s) => n + s.requirements.length)),
    NavTarget('Milestones', TView.milestones, count: ws.milestones.length + 1),
    NavTarget('Legacy notes', TView.legacy, count: ws.legacy.length),
  ];

  List<NavTarget> navLabels() => [
    for (final l in ws.labels) NavTarget(l, TView.tasks, byLabel: l, count: ws.tasks.where((t) => t.labels.contains(l)).length),
  ];

  int get inboxCount => inbox(ws, lastSeen()).length;

  bool isCurrent(NavTarget n) {
    if (n.view != view) return false;
    if (view != TView.tasks) return true;
    return n.byLabel != null ? labelFilter == n.byLabel : labelFilter == null && statusFilter == n.status;
  }

  void go(NavTarget n) {
    view = n.view;
    if (n.view == TView.tasks) {
      statusFilter = n.byLabel != null ? null : n.status;
      labelFilter = n.byLabel;
    }
    notifyListeners();
  }

  void showView(TView v) {
    view = v;
    notifyListeners();
  }

  void showStatus(String? status) => go(NavTarget('', TView.tasks, status: status));

  /// Something outside changed what the rows show (e.g. the inbox was marked seen).
  void refresh() => notifyListeners();

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setGroupBy(String g) {
    groupBy = g;
    notifyListeners();
  }

  // Selection --------------------------------------------------------------------------------------

  void select(Object? key) {
    selected = key;
    notifyListeners();
  }

  /// A click on a row: open it, or close it when it is already open.
  void toggle(Object? key) => select(selected == key ? null : key);

  void close() => select(null);

  /// Move the selection by [delta] items (J/K), opening the item in the panel. Returns the row
  /// index now selected, or null when there are no items.
  int? move(int delta) {
    final all = rows();
    final positions = [for (var i = 0; i < all.length; i++) if (!all[i].isHeader) i];
    if (positions.isEmpty) return null;
    final c = cursor;
    final i = c != null && c < positions.length && all[positions[c]].key == selected
        ? c
        : positions.indexWhere((p) => all[p].key == selected);
    final next = i < 0 ? (delta > 0 ? 0 : positions.length - 1) : (i + delta).clamp(0, positions.length - 1);
    cursor = next;
    selected = all[positions[next]].key;
    notifyListeners();
    return positions[next];
  }

  /// The next status / priority of the selected task, for S and P.
  String? nextStatus() {
    final t = selectedTask;
    if (t == null) return null;
    return ws.statuses[(ws.statuses.indexOf(t.status) + 1) % ws.statuses.length];
  }

  String? nextPriority() {
    final t = selectedTask;
    if (t == null) return null;
    const order = ['', 'low', 'medium', 'high'];
    return order[(order.indexOf(t.priority.toLowerCase()) + 1) % order.length];
  }

  // Rows -------------------------------------------------------------------------------------------

  static bool isOpen(Task t) => !t.archived && t.status != 'Done' && t.status != 'Dropped';

  bool _matches(String text) => query.isEmpty || text.toLowerCase().contains(query.toLowerCase());

  List<Task> get visibleTasks => ws.tasks.where((t) {
    if (labelFilter != null && !t.labels.contains(labelFilter)) return false;
    if (statusFilter == 'open' && !isOpen(t)) return false;
    if (statusFilter != null && statusFilter != 'open' && t.status != statusFilter) return false;
    return _matches('${t.id} ${t.title} ${t.labels.join(' ')}');
  }).toList();

  List<ListRow> rows() => switch (view) {
    TView.inbox => _inboxRows(),
    TView.tasks => _taskRows(),
    TView.legacy => _legacyRows(),
    TView.milestones => _milestoneRows(),
    TView.specs => _specRows(),
    TView.changes => _changeRows(),
  };

  /// Groups of [items] in [order], each a header and its items; empty groups are left out.
  static List<ListRow> grouped<T>(List<String> order, Map<String, List<T>> groups, Object Function(T) key,
      {String Function(String g)? title}) => [
    for (final g in order)
      if (groups[g]?.isNotEmpty ?? false) ...[
        ListRow.header(title?.call(g) ?? g, groups[g]!.length),
        for (final x in groups[g]!) ListRow.item(key(x), x as Object),
      ],
  ];

  static Map<String, List<T>> groupBy_<T>(Iterable<T> items, Iterable<String> Function(T) keys) {
    final m = <String, List<T>>{};
    for (final x in items) {
      for (final k in keys(x)) {
        m.putIfAbsent(k, () => []).add(x);
      }
    }
    return m;
  }

  static Object _inboxKey(InboxItem i) =>
      i.task?.id ??
      (i.change != null
          ? ChangeKey(i.change!.dir)
          : (i.legacy != null ? LegacyKey(i.legacy!.file, i.legacy!.line) : i.branch?.name ?? ''));

  List<ListRow> _inboxRows() {
    final items = inbox(ws, lastSeen())
        .where((i) => _matches('${i.task?.title ?? ''} ${i.change?.title ?? ''} ${i.legacy?.text ?? ''} ${i.why}'));
    return grouped([sinceSection, ...attentionSections], groupBy_(items, (i) => [i.section]), _inboxKey);
  }

  List<ListRow> _taskRows() {
    final tasks = visibleTasks;
    switch (groupBy) {
      case 'priority':
        final g = groupBy_(tasks, (t) => [t.priority.toLowerCase()]);
        return grouped(['high', 'medium', 'low', ''], g, (t) => t.id, title: (p) => p.isEmpty ? 'No priority' : p);
      case 'label':
        final g = groupBy_(tasks, (t) => t.labels.isEmpty ? [''] : t.labels);
        return grouped(g.keys.toList()..sort(), g, (t) => t.id, title: (l) => l.isEmpty ? 'No label' : l);
      default:
        return grouped(ws.statuses, groupBy_(tasks, (t) => [t.status]), (t) => t.id);
    }
  }

  List<ListRow> _legacyRows() {
    final items = ws.legacy.where((l) => _matches('${l.file} ${l.section} ${l.text} ${l.notes.join(' ')}')).toList();
    final groups = groupBy_(items, (l) => [l.group]);
    // Years first, newest on top; then the other notes files by name.
    bool year(String g) => RegExp(r'^\d{4}$').hasMatch(g);
    final order = groups.keys.toList()
      ..sort((a, b) => year(a) != year(b) ? (year(a) ? -1 : 1) : (year(a) ? b.compareTo(a) : a.compareTo(b)));
    return grouped(order, groups, (l) => LegacyKey(l.file, l.line));
  }

  List<ListRow> _milestoneRows() {
    final planned = [openMilestone, ...ws.milestones.reversed.where((m) => m.planned).map((m) => m.name)];
    final dated = ws.milestones.reversed.where((m) => !m.planned).map((m) => m.name);
    final title = ws.milestonesFromFile ? 'milestones.md' : 'By month of archiving';
    return grouped(
      ['Planned', title],
      {'Planned': planned.where(_matches).toList(), title: dated.where(_matches).toList()},
      (n) => MilestoneKey(n),
    );
  }

  List<ListRow> _specRows() => [
    for (final sp in ws.specs)
      ...grouped(
        [sp.capability],
        {sp.capability: sp.requirements.where((r) => _matches('${sp.capability} ${r.name} ${r.text}')).toList()},
        (r) => SpecKey(sp.capability, r.name),
      ),
  ];

  List<ListRow> _changeRows() {
    final list = ws.changes.where((c) => _matches('${c.id} ${c.title}'));
    return grouped(['Active', 'Draft', 'Completed'], groupBy_(list, (c) => [c.stage]), (c) => ChangeKey(c.dir));
  }

  String get title => switch (view) {
    TView.inbox => 'Inbox',
    TView.changes => 'Changes',
    TView.specs => 'Specs',
    TView.legacy => 'Legacy notes',
    TView.milestones => 'Milestones',
    TView.tasks when labelFilter != null => labelFilter!,
    TView.tasks => switch (statusFilter) {
      'open' => 'Open tasks',
      null => 'All tasks',
      final s => s,
    },
  };
}
