import 'package:material_ui/material_ui.dart';

import '../state/diff_prefs.dart';
import 'theme.dart';

enum Mode { pullRequest, changes, tasks, directories, help }

extension ModeText on Mode {
  String get label => switch (this) {
    Mode.pullRequest => 'Pull request',
    Mode.changes => 'Changes',
    Mode.tasks => 'Tasks',
    Mode.directories => 'Directories',
    Mode.help => 'Help',
  };

  String get explain => switch (this) {
    Mode.pullRequest => 'Review two revisions as a pull request: their commits, files and diff',
    Mode.changes => 'Your uncommitted work against HEAD: stage, discard, commit',
    Mode.tasks => 'Backlog.md tasks and OpenSpec changes, Linear-style',
    Mode.directories => 'Pick the Active Directory, the repo the other modes work on',
    Mode.help => 'Every key the app has (?)',
  };

  IconData get icon => switch (this) {
    Mode.pullRequest => Icons.merge_type,
    Mode.changes => Icons.edit_note,
    Mode.tasks => Icons.task_alt,
    Mode.directories => Icons.folder_outlined,
    Mode.help => Icons.help_outline,
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
    this.marked = false,
    this.cursor = false,
  });

  final IconData icon;
  final String label, tip;
  final bool selected, sub;

  /// Part of the current mode's group (the mode and its two views): lit with the mode's line. A
  /// sub entry that is also [selected] is the current view and gets a line twice as wide.
  final bool marked;

  /// The rail has the keyboard and its cursor is on this entry.
  final bool cursor;
  final VoidCallback onTap;
}

/// The left rail: the expand/collapse toggle, one entry per mode, and under Pull request or
/// Changes (while shown) the unified and side-by-side views. Collapsed: icons only, the tooltip names the
/// mode; expanded: labels, the tooltip explains the mode.
class ModeRail extends StatelessWidget {
  const ModeRail({
    super.key,
    required this.mode,
    required this.expanded,
    required this.layout,
    this.cursor,
    this.toggleCursor = false,
    required this.onSelect,
    required this.onToggle,
    required this.onLayout,
  });

  final Mode mode;
  final bool expanded;

  /// The diff layout shared by Pull request and Changes; null: not connected.
  final DiffLayout? layout;

  /// The mode under the cursor while the rail has the keyboard; null otherwise.
  final Mode? cursor;

  /// The rail has the keyboard and its cursor is on the expand / collapse button.
  final bool toggleCursor;
  final ValueChanged<Mode> onSelect;
  final VoidCallback onToggle;
  final ValueChanged<DiffLayout> onLayout;

  List<RailEntry> _entries() => [
    RailEntry(
      icon: expanded ? Icons.chevron_left : Icons.chevron_right,
      label: 'Collapse',
      tip: expanded ? 'Collapse the sidebar (Ctrl+B)' : 'Expand the sidebar (Ctrl+B)',
      selected: false,
      cursor: toggleCursor,
      onTap: onToggle,
    ),
    for (final m in Mode.values) ...[
      RailEntry(
        icon: m.icon,
        label: m.label,
        tip: expanded ? m.explain : m.label,
        selected: m == mode,
        cursor: m == cursor,
        onTap: () => onSelect(m),
      ),
      if (m == mode && _hasLayouts(m) && layout != null) ..._layouts(),
    ],
  ];

  /// The modes that show diffs.
  static bool _hasLayouts(Mode m) => m == Mode.pullRequest || m == Mode.changes;

  List<RailEntry> _layouts() => [
    for (final (l, icon, label) in [
      (DiffLayout.unified, Icons.subject, 'Unified'),
      (DiffLayout.sideBySide, Icons.compare, 'Side by side'),
    ])
      RailEntry(icon: icon, label: label, tip: '$label diff (v)', selected: layout == l, onTap: () => onLayout(l), sub: true, marked: true),
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
    final color = e.selected || e.cursor ? C.text : C.muted;
    final lit = e.selected || e.marked;
    final line = e.sub && e.selected ? 4.0 : 2.0; // the current view: twice as wide as the mode's line
    final left = (e.sub ? (expanded ? 26.0 : 14.0) : 13.0) - (line - 2); // the icons stay in line
    return Tooltip(
      message: e.tip,
      child: InkWell(
        onTap: e.onTap,
        child: Container(
          height: e.sub ? 32 : 44,
          padding: EdgeInsets.only(left: left),
          decoration: BoxDecoration(
            color: e.cursor ? C.surface2 : null,
            border: Border(left: BorderSide(color: lit ? C.accent : Colors.transparent, width: line)),
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
