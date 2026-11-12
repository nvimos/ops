import 'package:material_ui/material_ui.dart';

import '../../tasks/browser.dart';
import '../../tasks/inbox.dart';
import '../../tasks/markdown.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_parts.dart';
import 'icons.dart';
import 'rich.dart';

/// The main list's rows: group headers and items, fixed height so J/K can scroll to an index.
class TaskRows extends StatelessWidget {
  const TaskRows({
    super.key,
    required this.rows,
    required this.ws,
    required this.selected,
    required this.scroll,
    this.scrolls = true,
    required this.headerIcons,
    required this.onTap,
  });

  static const rowHeight = 36.0;

  final List<ListRow> rows;
  final Workspace ws;
  final Object? selected;
  final ScrollController scroll;

  /// False while the wheel steps through the rows instead (see `WheelMode`): no scrolling by it.
  final bool scrolls;

  /// Group titles are statuses or stages: show their icon.
  final bool headerIcons;
  final ValueChanged<Object?> onTap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Empty('Nothing here.');
    return ListView.builder(
      controller: scroll,
      physics: scrolls ? null : const NeverScrollableScrollPhysics(),
      itemExtent: rowHeight,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        if (r.isHeader) return GroupHeader(title: r.title!, count: r.count!, icon: headerIcons);
        final sel = r.key == selected;
        return HoverRow(
          selected: sel,
          onTap: () => onTap(r.key),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(height: rowHeight, child: rowContent(r.data!, ws)),
        );
      },
    );
  }
}

/// The row widget for what a list item holds.
Widget rowContent(Object data, Workspace ws) => switch (data) {
  Task t => TaskRow(t, ws),
  Change c => ChangeRow(c, ws),
  InboxItem i => InboxRow(i),
  LegacyItem l => LegacyRow(l, ws.promotedAs(l)),
  Requirement r => SpecRow(r, ws),
  String name => MilestoneRow(name, ws),
  _ => const SizedBox(),
};

class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.title, required this.count, required this.icon});

  final String title;
  final int count;
  final bool icon;

  @override
  Widget build(BuildContext context) => Container(
    color: C.surface,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        if (icon) ...[StatusIcon(title, size: 13), const SizedBox(width: 8)],
        Text(title, style: T.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text('$count', style: T.tiny),
      ],
    ),
  );
}

/// A fixed-width monospace id column.
class IdText extends StatelessWidget {
  const IdText(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 62,
    child: Text(
      id,
      style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.faint),
      overflow: TextOverflow.ellipsis,
    ),
  );
}

/// An icon with a tooltip, after a small gap.
class HintIcon extends StatelessWidget {
  const HintIcon(this.icon, this.tip, {super.key, this.color = C.muted});

  final IconData icon;
  final String tip;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Tooltip(message: tip, child: Icon(icon, size: 14, color: color)),
  );
}

class TaskRow extends StatelessWidget {
  const TaskRow(this.t, this.ws, {super.key});

  final Task t;
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final checks = [...t.acceptance, ...t.verify];
    final change = ws.changeFor(t);
    final branch = ws.branchFor(t);
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          PriorityIcon(t.priority),
          const SizedBox(width: 10),
          IdText(t.id),
          StatusIcon(t.status),
          const SizedBox(width: 10),
          Expanded(child: RichLine(t.title, maxLines: 1)),
          if (branch != null) HintIcon(Icons.call_split, branch, color: C.green),
          if (change != null) HintIcon(Icons.description_outlined, change.title, color: statusColor(change.stage)),
          if (box.maxWidth > 640)
            for (final l in t.labels.take(2)) Padding(padding: const EdgeInsets.only(left: 6), child: labelPill(l)),
          if (box.maxWidth > 420 && checks.isNotEmpty) _Checks(checks),
        ],
      ),
    );
  }
}

class _Checks extends StatelessWidget {
  const _Checks(this.checks);

  final List<Check> checks;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 10),
    child: Progress(checks.where((c) => c.done).length, checks.length, width: 30),
  );
}

class ChangeRow extends StatelessWidget {
  const ChangeRow(this.c, this.ws, {super.key});

  final Change c;
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final t = ws.taskFor(c);
    final date = c.archiveDate;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 560;
        return Row(
          children: [
            StatusIcon(c.stage),
            const SizedBox(width: 10),
            Expanded(child: RichLine(c.title, maxLines: 1)),
            if (c.deltas.isNotEmpty) ...[const SizedBox(width: 8), Pill('${c.deltas.length} req', color: C.purple)],
            if (wide && t != null) _Trailing(t.id, code: true),
            if (wide && date != null) _Trailing(fmtDate(date)),
            if (wide && c.allChecks.isNotEmpty) _Checks(c.allChecks),
          ],
        );
      },
    );
  }
}

/// Small text at the end of a row.
class _Trailing extends StatelessWidget {
  const _Trailing(this.text, {this.code = false});

  final String text;
  final bool code;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Text(text, style: code ? const TextStyle(fontSize: 11, fontFamily: mono, color: C.faint) : T.tiny),
  );
}

class InboxRow extends StatelessWidget {
  const InboxRow(this.i, {super.key});

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
        IdText(id),
        Expanded(child: RichLine(title, maxLines: 1)),
        const SizedBox(width: 10),
        Flexible(child: Text(i.why, style: T.tiny, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
      ],
    );
  }
}

class SpecRow extends StatelessWidget {
  const SpecRow(this.r, this.ws, {super.key});

  final Requirement r;
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final n = ws.changesTouching(r.name).length;
    final s = r.scenarios.length;
    return Row(
      children: [
        const Icon(Icons.rule, size: 15, color: C.muted),
        const SizedBox(width: 10),
        Expanded(child: RichLine(r.name, maxLines: 1)),
        if (s > 0) _Trailing('$s scenario${s == 1 ? '' : 's'}'),
        if (n > 0) _Trailing('$n change${n == 1 ? '' : 's'}'),
      ],
    );
  }
}

class LegacyRow extends StatelessWidget {
  const LegacyRow(this.l, this.promoted, {super.key});

  final LegacyItem l;
  final String? promoted;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Row(
      children: [
        Icon(
          l.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
          size: 15,
          color: l.done ? C.faint : C.muted,
        ),
        const SizedBox(width: 10),
        Expanded(child: RichLine(l.text, maxLines: 1, style: T.body.copyWith(color: l.done ? C.muted : C.text))),
        if (l.untested) ...[const SizedBox(width: 8), const Pill('untested', color: C.yellow)],
        if (promoted != null) _Promoted(promoted!),
        if (box.maxWidth > 560) _Section(l.section),
      ],
    ),
  );
}

class _Promoted extends StatelessWidget {
  const _Promoted(this.id);

  final String id;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Text(id, style: const TextStyle(fontSize: 11, fontFamily: mono, color: C.accent)),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 10),
    child: SizedBox(
      width: 160,
      child: Text(text, style: T.tiny, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
    ),
  );
}

class MilestoneRow extends StatelessWidget {
  const MilestoneRow(this.name, this.ws, {super.key});

  final String name;
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final list = milestoneChanges(ws, name);
    final date = ws.milestones.where((m) => m.name == name).firstOrNull?.date;
    final open = name == openMilestone;
    return Row(
      children: [
        Icon(open ? Icons.outlined_flag : Icons.flag, size: 15, color: open ? C.yellow : C.accent),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: T.body)),
        if (date != null) ...[Text(fmtDate(date), style: T.tiny), const SizedBox(width: 12)],
        Text('${list.length} changes', style: T.tiny),
        const SizedBox(width: 10),
        Progress(list.where((c) => c.stage == 'Completed').length, list.length, width: 50),
      ],
    );
  }
}
