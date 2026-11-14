import 'package:flutter/gestures.dart';
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
  /// sub entry that is also [selected] is the current view and is indented further than the other.
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
    this.onStep,
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

  /// The mouse wheel over the rail: -1 the previous mode, 1 the next (like Alt+[ and Alt+]).
  final ValueChanged<int>? onStep;
  final VoidCallback onToggle;
  final ValueChanged<DiffLayout> onLayout;

  static const double expandedWidth = 180, collapsedWidth = 48;

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

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || e.scrollDelta.dy == 0 || onStep == null) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) => onStep!(e.scrollDelta.dy > 0 ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return Listener(
      onPointerSignal: _wheel,
      child: _body(entries),
    );
  }

  Widget _body(List<RailEntry> entries) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: expanded ? ModeRail.expandedWidth : ModeRail.collapsedWidth,
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

  /// The views' indent is 10% less than the plain steps below (moved to the left).
  static const _pullLeft = 0.9;

  /// Where the icon starts. A mode sits at 13; its views are indented under it, and the current
  /// view is indented further.
  double _indent(RailEntry e) {
    if (!e.sub) return 13;
    final (view, current) = expanded ? (28.0, 38.0) : (20.0, 28.0);
    return (e.selected ? current : view) * _pullLeft;
  }

  /// While the rail animates from narrow to wide, the row is laid out at its final width and the
  /// rail clips it, so nothing overflows and the labels don't squash on the way.
  Widget _fixedWidth(double left, Widget row) {
    if (!expanded) return row;
    final w = ModeRail.expandedWidth - left - 2; // the entry's padding and its 2 px line
    return OverflowBox(alignment: Alignment.centerLeft, minWidth: w, maxWidth: w, child: row);
  }

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = e.selected || e.cursor ? C.text : C.muted;
    final lit = e.selected || e.marked;
    final left = _indent(e);
    return Tooltip(
      message: e.tip,
      child: InkWell(
        onTap: e.onTap,
        child: Container(
          height: e.sub ? 32 : 44,
          padding: EdgeInsets.only(left: left),
          decoration: BoxDecoration(
            color: e.cursor ? C.surface2 : null,
            border: Border(left: BorderSide(color: lit ? C.accent : Colors.transparent, width: 2)),
          ),
          child: _fixedWidth(
            left,
            Row(
              children: [
                Icon(e.icon, size: e.sub ? 16 : 20, color: color),
                if (expanded) const SizedBox(width: 10),
                if (expanded) Expanded(child: _Label(e.label, sub: e.sub, color: color)),
              ],
            ),
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
