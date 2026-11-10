import 'package:flutter/material.dart';

import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_parts.dart';
import 'icons.dart';
import 'rich.dart';
import 'task_detail.dart';

/// An OpenSpec change: Proposal, Spec (requirement cards), Design, Tasks.
class ChangeDetail extends StatefulWidget {
  const ChangeDetail({super.key, required this.change, required this.ws, required this.actions, this.onArchive});

  final Change change;
  final Workspace ws;
  final TaskActions actions;
  final Future<void> Function(Change c)? onArchive;

  @override
  State<ChangeDetail> createState() => _ChangeDetailState();
}

class _ChangeDetailState extends State<ChangeDetail> {
  int _tab = 0;
  bool _raw = false;

  @override
  void didUpdateWidget(ChangeDetail old) {
    super.didUpdateWidget(old);
    if (old.change.dir != widget.change.dir) {
      _tab = 0;
      _raw = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.change;
    final task = widget.ws.taskFor(c);
    final checks = c.allChecks;
    final tabs = [
      ('Proposal', c.proposal != null),
      ('Spec', c.deltas.isNotEmpty),
      ('Design', c.design != null),
      ('Tasks', c.tasks != null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          kicker: c.archived ? 'archived change' : 'change ${c.id}',
          title: c.title,
          onClose: widget.actions.close,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Column(
            children: [
              Prop(
                'Stage',
                Row(
                  children: [
                    StatusIcon(c.stage),
                    const SizedBox(width: 8),
                    Text(c.stage, style: T.body),
                  ],
                ),
              ),
              Prop('Status', Text(c.status, style: T.body)),
              if (task != null)
                Prop(
                  'Task',
                  LinkChip(
                    icon: Icons.task_alt,
                    label: '${task.id}  ${task.title}',
                    onTap: () => widget.actions.openTask(task.id),
                  ),
                ),
              if (c.archiveDate != null) Prop('Archived', Text(_date(c.archiveDate!), style: T.small)),
              if (checks.isNotEmpty)
                Prop('Progress', Progress(checks.where((x) => x.done).length, checks.length, width: 120)),
              Prop('Folder', Text(c.dir, style: T.small, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.border)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                if (tabs[i].$2) _Tab(tabs[i].$1, selected: _tab == i, onTap: () => setState(() => _tab = i)),
            ],
          ),
        ),
        Expanded(child: _raw ? _rawView(c) : _body(c)),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: C.border)),
          ),
          child: Row(
            children: [
              SmallButton(
                'Open in Neovim',
                icon: Icons.open_in_new,
                onPressed: () {
                  final doc = _docOfTab(c);
                  if (doc != null) widget.actions.openInNeovim(doc.path, 1);
                },
              ),
              const SizedBox(width: 8),
              SmallButton(_raw ? 'Rendered' : 'View raw', onPressed: () => setState(() => _raw = !_raw)),
              const Spacer(),
              if (!c.archived && widget.onArchive != null)
                SmallButton(
                  'Archive into spec',
                  icon: Icons.inventory_2_outlined,
                  primary: true,
                  onPressed: () => widget.onArchive!(c),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Doc? _docOfTab(Change c) => switch (_tab) {
    2 => c.design,
    3 => c.tasks,
    _ => c.proposal,
  };

  Widget _rawView(Change c) {
    final d = _docOfTab(c);
    if (d == null) return const Empty('No file');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [SelectableText(d.lines.join('\n'), style: T.code)],
    );
  }

  Widget _body(Change c) {
    final a = widget.actions;
    switch (_tab) {
      case 1:
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          children: [
            for (final d in c.deltas)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RequirementCard(delta: d),
              ),
          ],
        );
      case 2:
        final d = c.design!;
        return ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            for (final s in d.sections.where((s) => s.level == 2))
              DetailSection(s.title, Blocks(d.body(s), onTask: a.openTask)),
          ],
        );
      case 3:
        return ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            for (final (title, checks) in c.checkGroups)
              DetailSection(
                title,
                Column(
                  children: [
                    for (final ch in checks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: CheckRow(ch, onTap: () => a.toggleCheck(c.tasks!.path, ch), onTask: a.openTask),
                      ),
                  ],
                ),
                trailing: Progress(checks.where((x) => x.done).length, checks.length),
              ),
          ],
        );
      default:
        final p = c.proposal;
        if (p == null) return const Empty('No proposal.md');
        return ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            for (final s in p.sections.where((s) => s.level == 2 && s.title.toLowerCase() != 'original notes'))
              DetailSection(s.title, Blocks(p.body(s), onTask: a.openTask)),
          ],
        );
    }
  }
}

String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _Tab extends StatelessWidget {
  const _Tab(this.label, {required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: selected ? C.accent : Colors.transparent, width: 2)),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, color: selected ? C.text : C.muted)),
    ),
  );
}

/// A requirement as a card with an Added / Modified / Removed pill, its text and scenarios.
class RequirementCard extends StatelessWidget {
  const RequirementCard({super.key, this.delta, this.requirement, this.footer});

  final Delta? delta;
  final Requirement? requirement;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final r = delta?.requirement ?? requirement!;
    final (label, color) = switch (delta?.op) {
      DeltaOp.added => ('Added', C.green),
      DeltaOp.modified => ('Modified', C.yellow),
      DeltaOp.removed => ('Removed', C.red),
      DeltaOp.renamed => ('Renamed', C.purple),
      null => ('', C.muted),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (label.isNotEmpty) ...[Pill(label, color: color), const SizedBox(width: 8)],
              Expanded(child: Text(r.name, style: T.title.copyWith(fontSize: 13.5))),
              if (delta != null) Text(delta!.capability, style: T.tiny),
            ],
          ),
          if (r.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            RichLine(
              r.text,
              style: T.body.copyWith(
                height: 1.45,
                color: delta?.op == DeltaOp.removed ? C.muted : C.text,
                decoration: delta?.op == DeltaOp.removed ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
          for (final s in r.scenarios) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(5)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.play_arrow_rounded, size: 14, color: C.muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          s.name,
                          style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final step in s.steps)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: RichLine(step, style: T.small),
                    ),
                ],
              ),
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }
}
