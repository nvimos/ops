import 'package:flutter/material.dart';

import '../../tasks/markdown.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'change_detail.dart';
import 'detail_parts.dart';
import 'icons.dart';
import 'rich.dart';
import 'task_detail.dart';

enum TView { tasks, changes }

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
  TView view = TView.tasks;
  String? statusFilter = 'open'; // 'open', a status, or null for all
  String? labelFilter;
  String groupBy = 'status';
  String query = '';
  Object? selected; // Task id (String) or Change dir (ChangeKey)

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
  Future<void> setStatus(Task t, String status) async => _snack('read-only for now');

  @override
  Future<void> setPriority(Task t, String priority) async => _snack('read-only for now');

  @override
  Future<void> toggleCheck(String path, Check c) async => _snack('read-only for now');

  @override
  Future<void> review(Task t, String branch) async => widget.onReview?.call(t, branch);

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
    if (view == TView.changes) return 'Changes';
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
    return ListenableBuilder(
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
      if (c != null) return ChangeDetail(change: c, ws: ws, actions: this);
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
        item(
          'Open tasks',
          Icons.inbox_outlined,
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
                  itemCount: rs.length,
                  itemBuilder: (context, i) {
                    final r = rs[i];
                    if (r.isHeader) {
                      return Container(
                        color: C.surface,
                        padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
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
                      onTap: () => setState(() => selected = sel ? null : r.key),
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
