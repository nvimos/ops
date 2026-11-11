import 'package:flutter/material.dart';

import '../../tasks/browser.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_parts.dart';
import 'icons.dart';
import 'rich.dart';
import 'task_detail.dart';

/// The tabs of a change: each shows one of its files, when it has that file.
enum ChangeTab {
  proposal('Proposal'),
  spec('Spec'),
  design('Design'),
  tasks('Tasks');

  const ChangeTab(this.label);
  final String label;

  bool shownFor(Change c) => switch (this) {
    proposal => c.proposal != null,
    spec => c.deltas.isNotEmpty,
    design => c.design != null,
    tasks => c.tasks != null,
  };

  /// The file "Open in Neovim" and "View raw" use.
  Doc? docOf(Change c) => switch (this) {
    design => c.design,
    tasks => c.tasks,
    _ => c.proposal,
  };
}

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
  ChangeTab _tab = ChangeTab.proposal;
  bool _raw = false;

  Change get c => widget.change;

  @override
  void didUpdateWidget(ChangeDetail old) {
    super.didUpdateWidget(old);
    if (old.change.dir == widget.change.dir) return;
    _tab = ChangeTab.proposal;
    _raw = false;
  }

  void _select(ChangeTab t) => setState(() => _tab = t);

  void _toggleRaw() => setState(() => _raw = !_raw);

  void _open() {
    final doc = _tab.docOf(c);
    if (doc != null) widget.actions.openInNeovim(doc.path, 1);
  }

  void _archive() => widget.onArchive?.call(c);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PanelHeader(kicker: c.archived ? 'archived change' : 'change ${c.id}', title: c.title, onClose: widget.actions.close),
      _ChangeProps(change: c, task: widget.ws.taskFor(c), onTask: widget.actions.openTask),
      _TabBar(tabs: ChangeTab.values.where((t) => t.shownFor(c)).toList(), selected: _tab, onSelect: _select),
      Expanded(child: _raw ? _RawView(_tab.docOf(c)) : _body()),
      _ChangeFooter(
        raw: _raw,
        onOpen: _open,
        onRaw: _toggleRaw,
        onArchive: !c.archived && widget.onArchive != null ? _archive : null,
      ),
    ],
  );

  Widget _body() {
    final a = widget.actions;
    return switch (_tab) {
      ChangeTab.spec => _SpecTab(c.deltas),
      ChangeTab.design => _SectionsTab(doc: c.design!, onTask: a.openTask),
      ChangeTab.tasks => _TasksTab(change: c, actions: a),
      ChangeTab.proposal when c.proposal == null => const Empty('No proposal.md'),
      ChangeTab.proposal => _SectionsTab(doc: c.proposal!, onTask: a.openTask, skip: 'original notes'),
    };
  }
}

// Organisms ----------------------------------------------------------------------------------------

class _ChangeProps extends StatelessWidget {
  const _ChangeProps({required this.change, required this.task, required this.onTask});

  final Change change;
  final Task? task;
  final ValueChanged<String> onTask;

  @override
  Widget build(BuildContext context) {
    final c = change, t = task, checks = c.allChecks;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Column(
        children: [
          Prop('Stage', _Stage(c.stage)),
          Prop('Status', Text(c.status, style: T.body)),
          if (t != null) Prop('Task', LinkChip(icon: Icons.task_alt, label: '${t.id}  ${t.title}', onTap: () => onTask(t.id))),
          if (c.archiveDate != null) Prop('Archived', Text(fmtDate(c.archiveDate!), style: T.small)),
          if (checks.isNotEmpty) Prop('Progress', Progress(checks.where((x) => x.done).length, checks.length, width: 120)),
          Prop('Folder', Text(c.dir, style: T.small, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tabs, required this.selected, required this.onSelect});

  final List<ChangeTab> tabs;
  final ChangeTab selected;
  final ValueChanged<ChangeTab> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
    child: Row(
      children: [for (final t in tabs) TabLabel(t.label, selected: t == selected, onTap: () => onSelect(t))],
    ),
  );
}

class _ChangeFooter extends StatelessWidget {
  const _ChangeFooter({required this.raw, required this.onOpen, required this.onRaw, required this.onArchive});

  final bool raw;
  final VoidCallback onOpen, onRaw;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) => PanelFooter(
    children: [
      SmallButton('Open in Neovim', icon: Icons.open_in_new, onPressed: onOpen),
      const SizedBox(width: 8),
      SmallButton(raw ? 'Rendered' : 'View raw', onPressed: onRaw),
      const Spacer(),
      if (onArchive != null)
        SmallButton('Archive into spec', icon: Icons.inventory_2_outlined, primary: true, onPressed: onArchive),
    ],
  );
}

/// The level-2 sections of a file as typed blocks; [skip] leaves one section out by title.
class _SectionsTab extends StatelessWidget {
  const _SectionsTab({required this.doc, required this.onTask, this.skip});

  final Doc doc;
  final ValueChanged<String> onTask;
  final String? skip;

  @override
  Widget build(BuildContext context) {
    final sections = doc.sections.where((s) => s.level == 2 && s.title.toLowerCase() != skip).toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 30),
      itemCount: sections.length,
      itemBuilder: (_, i) => DetailSection(sections[i].title, Blocks(doc.body(sections[i]), onTask: onTask)),
    );
  }
}

class _SpecTab extends StatelessWidget {
  const _SpecTab(this.deltas);

  final List<Delta> deltas;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
    itemCount: deltas.length,
    itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: RequirementCard(delta: deltas[i])),
  );
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({required this.change, required this.actions});

  final Change change;
  final TaskActions actions;

  @override
  Widget build(BuildContext context) {
    final groups = change.checkGroups;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 30),
      itemCount: groups.length,
      itemBuilder: (_, i) => ChecksSection(
        title: groups[i].$1,
        checks: groups[i].$2,
        onCheck: (ch) => actions.toggleCheck(change.tasks!.path, ch),
        onTask: actions.openTask,
      ),
    );
  }
}

class _RawView extends StatelessWidget {
  const _RawView(this.doc);

  final Doc? doc;

  @override
  Widget build(BuildContext context) {
    if (doc == null) return const Empty('No file');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [SelectableText(doc!.lines.join('\n'), style: T.code)],
    );
  }
}

// Molecules and atoms --------------------------------------------------------------------------------

class _Stage extends StatelessWidget {
  const _Stage(this.stage);

  final String stage;

  @override
  Widget build(BuildContext context) => Row(
    children: [StatusIcon(stage), const SizedBox(width: 8), Text(stage, style: T.body)],
  );
}

/// A tab title with an accent underline when selected.
class TabLabel extends StatelessWidget {
  const TabLabel(this.label, {super.key, required this.selected, required this.onTap});

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

/// How a delta's operation shows: pill text and color.
(String, Color) deltaLook(DeltaOp? op) => switch (op) {
  DeltaOp.added => ('Added', C.green),
  DeltaOp.modified => ('Modified', C.yellow),
  DeltaOp.removed => ('Removed', C.red),
  DeltaOp.renamed => ('Renamed', C.purple),
  null => ('', C.muted),
};

/// A requirement as a card with an Added / Modified / Removed pill, its text and scenarios.
class RequirementCard extends StatelessWidget {
  const RequirementCard({super.key, this.delta, this.requirement, this.footer});

  final Delta? delta;
  final Requirement? requirement;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final r = delta?.requirement ?? requirement!;
    final removed = delta?.op == DeltaOp.removed;
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
          _CardTitle(name: r.name, op: delta?.op, capability: delta?.capability),
          if (r.text.isNotEmpty) _RequirementText(r.text, removed: removed),
          for (final s in r.scenarios) ScenarioBox(s),
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.name, required this.op, required this.capability});

  final String name;
  final DeltaOp? op;
  final String? capability;

  @override
  Widget build(BuildContext context) {
    final (label, color) = deltaLook(op);
    return Row(
      children: [
        if (label.isNotEmpty) ...[Pill(label, color: color), const SizedBox(width: 8)],
        Expanded(child: Text(name, style: T.title.copyWith(fontSize: 13.5))),
        if (capability != null) Text(capability!, style: T.tiny),
      ],
    );
  }
}

class _RequirementText extends StatelessWidget {
  const _RequirementText(this.text, {required this.removed});

  final String text;
  final bool removed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: RichLine(
      text,
      style: T.body.copyWith(
        height: 1.45,
        color: removed ? C.muted : C.text,
        decoration: removed ? TextDecoration.lineThrough : null,
      ),
    ),
  );
}

/// A scenario: its name and steps on a darker box.
class ScenarioBox extends StatelessWidget {
  const ScenarioBox(this.scenario, {super.key});

  final Scenario scenario;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(5)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.play_arrow_rounded, size: 14, color: C.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(scenario.name, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w500))),
          ],
        ),
        const SizedBox(height: 4),
        for (final step in scenario.steps) Padding(padding: const EdgeInsets.only(top: 2), child: RichLine(step, style: T.small)),
      ],
    ),
  );
}

/// A change as a clickable line: stage, optional delta pill, title, task id, archive date.
class ChangeLine extends StatelessWidget {
  const ChangeLine({super.key, required this.change, required this.onTap, this.op, this.taskId, this.indent = 20});

  final Change change;
  final VoidCallback onTap;
  final DeltaOp? op;
  final String? taskId;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final (label, color) = deltaLook(op);
    final date = change.archiveDate;
    return HoverRow(
      onTap: onTap,
      padding: EdgeInsets.symmetric(horizontal: indent, vertical: 7),
      child: Row(
        children: [
          StatusIcon(change.stage, size: 13),
          const SizedBox(width: 8),
          if (label.isNotEmpty) ...[Pill(label, color: color), const SizedBox(width: 8)],
          Expanded(child: RichLine(change.title, maxLines: 1)),
          if (taskId != null) Text(taskId!, style: const TextStyle(fontSize: 11, fontFamily: mono, color: C.faint)),
          if (date != null) Text('  ${fmtDate(date)}', style: T.tiny),
        ],
      ),
    );
  }
}
