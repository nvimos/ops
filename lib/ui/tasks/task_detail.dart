import 'package:flutter/material.dart';

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
  void openInNeovim(String path, int line);
  Future<void> setStatus(Task t, String status);
  Future<void> setPriority(Task t, String priority);
  Future<void> toggleCheck(String path, Check c);
  Future<void> review(Task t, String branch);
}

class TaskDetail extends StatelessWidget {
  const TaskDetail({super.key, required this.task, required this.ws, required this.actions});

  final Task task;
  final Workspace ws;
  final TaskActions actions;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final change = ws.changeFor(t);
    final branch = ws.branchFor(t);
    void onCheck(Check c) => actions.toggleCheck(t.path, c);
    final ac = t.acceptance, verify = t.verify, dod = t.definitionOfDone;
    final notes = t.originalNotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          kicker: t.id,
          title: t.title,
          onClose: actions.close,
          actions: [
            Tooltip(
              message: 'Open the task file in Neovim',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 17,
                onPressed: () => actions.openInNeovim(t.path, 1),
                icon: const Icon(Icons.open_in_new, color: C.muted),
              ),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: Column(
                  children: [
                    Prop(
                      'Status',
                      _StatusMenu(value: t.status, options: ws.statuses, onPick: (s) => actions.setStatus(t, s)),
                    ),
                    Prop('Priority', _PriorityMenu(value: t.priority, onPick: (p) => actions.setPriority(t, p))),
                    if (t.labels.isNotEmpty) Prop('Labels', pillRow(t.labels.map(labelPill).toList())),
                    if (change != null)
                      Prop(
                        'Change',
                        LinkChip(
                          icon: Icons.description_outlined,
                          label: change.title,
                          onTap: () => actions.openChange(change),
                        ),
                      ),
                    if (t.dependencies.isNotEmpty)
                      Prop(
                        'Blocked by',
                        pillRow([
                          for (final d in t.dependencies)
                            LinkChip(icon: Icons.link, label: d, onTap: () => actions.openTask(d)),
                        ]),
                      ),
                    Prop(
                      'Branch',
                      branch == null
                          ? const Text('none linked (name a branch task-<n>)', style: T.small)
                          : Row(
                              children: [
                                Flexible(
                                  child: LinkChip(icon: Icons.call_split, label: branch),
                                ),
                                const SizedBox(width: 8),
                                if ((ws.ahead[branch] ?? 0) > 0)
                                  Text('${ws.ahead[branch]} commits ahead', style: T.tiny),
                                const Spacer(),
                                SmallButton(
                                  'Review',
                                  icon: Icons.merge_type,
                                  primary: true,
                                  onPressed: () => actions.review(t, branch),
                                ),
                              ],
                            ),
                    ),
                    if (t.created.isNotEmpty) Prop('Created', Text(t.created, style: T.small)),
                    Prop(
                      'File',
                      InkWell(
                        onTap: () => actions.openInNeovim(t.path, 1),
                        child: Text(
                          t.path,
                          style: const TextStyle(fontSize: 12, color: C.accent),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (t.description.isNotEmpty)
                DetailSection('Description', Blocks(t.description, onTask: actions.openTask, onCheck: onCheck)),
              if (ac.isNotEmpty)
                DetailSection(
                  'Acceptance criteria',
                  _Checks(ac, onCheck, actions.openTask),
                  trailing: Progress(ac.where((c) => c.done).length, ac.length),
                ),
              if (verify.isNotEmpty)
                DetailSection(
                  'Verify',
                  _Checks(verify, onCheck, actions.openTask),
                  trailing: Progress(verify.where((c) => c.done).length, verify.length),
                ),
              if (dod.isNotEmpty)
                DetailSection(
                  'Definition of done',
                  _Checks(dod, onCheck, actions.openTask),
                  trailing: Progress(dod.where((c) => c.done).length, dod.length),
                ),
              for (final s in t.otherSections)
                DetailSection(
                  s.title,
                  Blocks(blocksIn(t.lines, s.start + 1, s.end), onTask: actions.openTask, onCheck: onCheck),
                ),
              if (notes.isNotEmpty) _OriginalNotes(notes),
            ],
          ),
        ),
      ],
    );
  }
}

class _Checks extends StatelessWidget {
  const _Checks(this.checks, this.onCheck, this.onTask);

  final List<Check> checks;
  final void Function(Check) onCheck;
  final void Function(String) onTask;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final c in checks)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: CheckRow(c, onTap: () => onCheck(c), onTask: onTask),
        ),
    ],
  );
}

class _OriginalNotes extends StatefulWidget {
  const _OriginalNotes(this.lines);

  final List<String> lines;

  @override
  State<_OriginalNotes> createState() => _OriginalNotesState();
}

class _OriginalNotesState extends State<_OriginalNotes> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return DetailSection(
      'Original notes',
      _open
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(5)),
              child: SelectableText(widget.lines.join('\n'), style: T.code.copyWith(fontSize: 12, color: C.muted)),
            )
          : const SizedBox.shrink(),
      trailing: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Text(
          _open ? 'hide' : 'show ${widget.lines.length} lines',
          style: const TextStyle(fontSize: 12, color: C.accent),
        ),
      ),
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.value, required this.options, required this.onPick});

  final String value;
  final List<String> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Status (S)',
      color: C.surface2,
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final s in options)
          PopupMenuItem(
            value: s,
            height: 32,
            child: Row(
              children: [
                StatusIcon(s),
                const SizedBox(width: 8),
                Text(s, style: T.body),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusIcon(value),
          const SizedBox(width: 8),
          Text(value, style: T.body),
        ],
      ),
    );
  }
}

class _PriorityMenu extends StatelessWidget {
  const _PriorityMenu({required this.value, required this.onPick});

  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    String label(String p) => p.isEmpty ? 'No priority' : p[0].toUpperCase() + p.substring(1);
    return PopupMenuButton<String>(
      tooltip: 'Priority (P)',
      color: C.surface2,
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final p in priorities)
          PopupMenuItem(
            value: p,
            height: 32,
            child: Row(
              children: [
                PriorityIcon(p),
                const SizedBox(width: 8),
                Text(label(p), style: T.body),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PriorityIcon(value),
          const SizedBox(width: 8),
          Text(label(value), style: value.isEmpty ? T.small : T.body),
        ],
      ),
    );
  }
}
