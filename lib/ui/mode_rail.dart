import 'package:flutter/material.dart';

import '../state/pr.dart';
import 'theme.dart';

enum Mode { pullRequest, changes, tasks, directories }

extension ModeText on Mode {
  String get label => switch (this) {
    Mode.pullRequest => 'Pull request',
    Mode.changes => 'Changes',
    Mode.tasks => 'Tasks',
    Mode.directories => 'Directories',
  };

  String get explain => switch (this) {
    Mode.pullRequest => 'Review two revisions as a pull request: their commits, files and diff',
    Mode.changes => 'Your uncommitted work against HEAD: stage, discard, commit',
    Mode.tasks => 'Backlog.md tasks and OpenSpec changes, Linear-style',
    Mode.directories => 'Pick the Active Directory, the repo the other modes work on',
  };

  IconData get icon => switch (this) {
    Mode.pullRequest => Icons.merge_type,
    Mode.changes => Icons.edit_note,
    Mode.tasks => Icons.view_kanban_outlined,
    Mode.directories => Icons.folder_outlined,
  };
}

/// One entry of the rail.
class RailEntry {
  const RailEntry({
    required this.icon,
    required this.label,
    required this.tip,
    required this.selected,
    required this.onTap,
    this.sub = false,
  });

  final IconData icon;
  final String label, tip;
  final bool selected, sub;
  final VoidCallback onTap;
}

/// The left rail: the expand/collapse toggle, one entry per mode, and under Pull request (while
/// it is shown) the unified and side-by-side views. Collapsed: icons only, the tooltip names the
/// mode; expanded: labels, the tooltip explains the mode.
class ModeRail extends StatelessWidget {
  const ModeRail({
    super.key,
    required this.mode,
    required this.expanded,
    required this.layout,
    required this.onSelect,
    required this.onToggle,
    required this.onLayout,
  });

  final Mode mode;
  final bool expanded;

  /// The Pull request diff layout; null: no Pull request state yet (not connected).
  final DiffLayout? layout;
  final ValueChanged<Mode> onSelect;
  final VoidCallback onToggle;
  final ValueChanged<DiffLayout> onLayout;

  List<RailEntry> _entries() => [
    RailEntry(
      icon: expanded ? Icons.chevron_left : Icons.chevron_right,
      label: 'Collapse',
      tip: expanded ? 'Collapse the sidebar (Ctrl+B)' : 'Expand the sidebar (Ctrl+B)',
      selected: false,
      onTap: onToggle,
    ),
    for (final m in Mode.values) ...[
      RailEntry(
        icon: m.icon,
        label: m.label,
        tip: expanded ? m.explain : m.label,
        selected: m == mode,
        onTap: () => onSelect(m),
      ),
      if (m == Mode.pullRequest && mode == Mode.pullRequest && layout != null) ..._layouts(),
    ],
  ];

  List<RailEntry> _layouts() => [
    for (final (l, icon, label) in [
      (DiffLayout.unified, Icons.view_agenda_outlined, 'Unified'),
      (DiffLayout.sideBySide, Icons.vertical_split_outlined, 'Side by side'),
    ])
      RailEntry(icon: icon, label: label, tip: '$label diff (v)', selected: layout == l, onTap: () => onLayout(l), sub: true),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: expanded ? 180 : 48,
      color: C.surface,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4),
        itemCount: entries.length,
        itemBuilder: (context, i) => RailItem(entry: entries[i], expanded: expanded),
      ),
    );
  }
}

class RailItem extends StatelessWidget {
  const RailItem({super.key, required this.entry, required this.expanded});

  final RailEntry entry;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = e.selected ? C.text : C.muted;
    return Tooltip(
      message: e.tip,
      child: InkWell(
        onTap: e.onTap,
        child: Container(
          height: e.sub ? 32 : 44,
          padding: EdgeInsets.only(left: e.sub ? (expanded ? 26 : 14) : 13),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: e.selected ? C.accent : Colors.transparent, width: 2)),
          ),
          child: Row(
            children: [
              Icon(e.icon, size: e.sub ? 16 : 20, color: color),
              if (expanded) const SizedBox(width: 10),
              if (expanded) Expanded(child: _Label(e.label, sub: e.sub, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.sub, required this.color});

  final String text;
  final bool sub;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Text(text, overflow: TextOverflow.ellipsis, style: (sub ? T.small : T.body).copyWith(color: color));
}
