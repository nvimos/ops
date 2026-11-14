import 'package:material_ui/material_ui.dart';

import '../../tasks/markdown.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_parts.dart';
import 'icons.dart';
import 'rich.dart';

/// What the detail panels can ask the Tasks view to do.
abstract class TaskActions {
  void openTask(String id);
  void openChange(Change c);
  void close();

  /// The detail panel's widen / narrow toggle.
  PanelWiden get widen;
  void openInNeovim(String path, int line);
  Future<void> setStatus(Task t, String status);
  Future<void> setPriority(Task t, String priority);
  Future<void> toggleCheck(String path, Check c, {bool cycle = false});
  Future<void> review(Task t, String branch);
  Future<void> linkBranch(Task t, String? branch);
}

String priorityLabel(String p) => p.isEmpty ? 'No priority' : p[0].toUpperCase() + p.substring(1);

/// A Backlog.md task: properties, then its sections, checklists and original notes.
class TaskDetail extends StatelessWidget {
  const TaskDetail({super.key, required this.task, required this.ws, required this.actions});

  final Task task;
  final Workspace ws;
  final TaskActions actions;

  void _check(Check c, bool cycle) => actions.toggleCheck(task.path, c, cycle: cycle);

  @override
  Widget build(BuildContext context) {
    final t = task;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          kicker: t.id,
          title: t.title,
          onClose: actions.close,
          widen: actions.widen,
          actions: [OpenInNeovimButton(onTap: () => actions.openInNeovim(t.path, 1))],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              _TaskProps(task: t, ws: ws, actions: actions),
              const Divider(height: 1),
              ..._sections(),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _sections() {
    final t = task;
    return [
      if (t.description.isNotEmpty)
        DetailSection('Description', Blocks(t.description, onTask: actions.openTask, onCheck: _check)),
      for (final (title, checks) in [
        ('Acceptance criteria', t.acceptance),
        ('Verify', t.verify),
        ('Definition of done', t.definitionOfDone),
      ])
        if (checks.isNotEmpty) ChecksSection(title: title, checks: checks, onCheck: _check, onTask: actions.openTask),
      for (final s in t.otherSections)
        DetailSection(s.title, Blocks(blocksIn(t.lines, s.start + 1, s.end), onTask: actions.openTask, onCheck: _check)),
      if (t.originalNotes.isNotEmpty) _OriginalNotes(t.originalNotes),
    ];
  }
}

/// The properties block: status, priority, labels, links, branch, dates, file.
class _TaskProps extends StatelessWidget {
  const _TaskProps({required this.task, required this.ws, required this.actions});

  final Task task;
  final Workspace ws;
  final TaskActions actions;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final change = ws.changeFor(t);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Column(
        children: [
          Prop('Status', _statusMenu()),
          Prop('Priority', _priorityMenu()),
          if (t.labels.isNotEmpty) Prop('Labels', pillRow(t.labels.map(labelPill).toList())),
          if (change != null)
            Prop('Change', LinkChip(icon: Icons.description_outlined, label: change.title, onTap: () => actions.openChange(change))),
          if (t.dependencies.isNotEmpty) Prop('Blocked by', _dependencies()),
          Prop('Branch', _BranchProp(task: t, ws: ws, actions: actions)),
          if (t.created.isNotEmpty) Prop('Created', Text(t.created, style: T.small)),
          Prop('File', LinkText(
              t.path,
              tooltip: 'open in Neovim; Ctrl+click: in a new nvim-qt',
              onTap: () => actions.openInNeovim(t.path, 1),
            )),
        ],
      ),
    );
  }

  Widget _statusMenu() => ChoiceMenu(
    value: task.status,
    options: ws.statuses,
    icon: StatusIcon.new,
    label: (s) => s,
    tip: 'Status (S)',
    onPick: (s) => actions.setStatus(task, s),
  );

  Widget _priorityMenu() => ChoiceMenu(
    value: task.priority,
    options: priorities,
    icon: PriorityIcon.new,
    label: priorityLabel,
    tip: 'Priority (P)',
    onPick: (p) => actions.setPriority(task, p),
  );

  Widget _dependencies() => pillRow([
    for (final d in task.dependencies) LinkChip(icon: Icons.link, label: d, onTap: () => actions.openTask(d)),
  ]);
}

/// The task's branch with Review, commits ahead and Unlink; or a menu to link one.
class _BranchProp extends StatelessWidget {
  const _BranchProp({required this.task, required this.ws, required this.actions});

  final Task task;
  final Workspace ws;
  final TaskActions actions;

  @override
  Widget build(BuildContext context) {
    final branch = ws.branchFor(task);
    if (branch == null) return _LinkBranchMenu(branches: _candidates(), onPick: (b) => actions.linkBranch(task, b));
    final ahead = ws.ahead[branch] ?? 0;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: LinkChip(icon: Icons.call_split, label: branch, onTap: () => actions.review(task, branch)),
          ),
        ),
        if (ahead > 0) Text('  $ahead commit${ahead == 1 ? '' : 's'} ahead', style: T.tiny),
        if (ws.links[task.id] == branch) _UnlinkButton(onTap: () => actions.linkBranch(task, null)),
        const SizedBox(width: 8),
        SmallButton('Review', icon: Icons.merge_type, primary: true, onPressed: () => actions.review(task, branch)),
      ],
    );
  }

  List<String> _candidates() => [
    for (final b in ws.branches?.list ?? []) if (b.name != ws.defaultBranch) b.name,
  ];
}

class _LinkBranchMenu extends StatelessWidget {
  const _LinkBranchMenu({required this.branches, required this.onPick});

  final List<String> branches;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Link a branch',
    color: C.surface2,
    onSelected: onPick,
    itemBuilder: (_) => [for (final b in branches) PopupMenuItem(value: b, height: 32, child: Text(b, style: T.body))],
    child: const Text('Link a branch…', style: TextStyle(fontSize: 12, color: C.accent)),
  );
}

class _UnlinkButton extends StatelessWidget {
  const _UnlinkButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Unlink',
    visualDensity: VisualDensity.compact,
    iconSize: 14,
    onPressed: onTap,
    icon: const Icon(Icons.link_off, color: C.muted),
  );
}

/// The notes the task was promoted from, folded until asked for.
class _OriginalNotes extends StatefulWidget {
  const _OriginalNotes(this.lines);

  final List<String> lines;

  @override
  State<_OriginalNotes> createState() => _OriginalNotesState();
}

class _OriginalNotesState extends State<_OriginalNotes> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) => DetailSection(
    'Original notes',
    _open ? _NotesBox(widget.lines) : const SizedBox.shrink(),
    trailing: LinkText(_open ? 'hide' : 'show ${widget.lines.length} lines', onTap: _toggle),
  );
}

class _NotesBox extends StatelessWidget {
  const _NotesBox(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(5)),
    child: Text(lines.join('\n'), style: T.code.copyWith(fontSize: 12, color: C.muted)),
  );
}
