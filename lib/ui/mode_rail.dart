import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

enum Mode { pullRequest, changes, addIgnore, history, tasks, repos, settings, log, help }

extension ModeText on Mode {
  String get label => switch (this) {
    Mode.pullRequest => 'Pull request',
    Mode.changes => 'Changes',
    Mode.addIgnore => 'Add and Ignore',
    Mode.history => 'History',
    Mode.tasks => 'Tasks',
    Mode.repos => 'Repos',
    Mode.settings => 'Settings',
    Mode.log => 'Log',
    Mode.help => 'Help',
  };

  String get explain => switch (this) {
    Mode.pullRequest => 'Review two revisions as a pull request: their commits, files and diff',
    Mode.changes => 'Your uncommitted work against HEAD: stage, discard, commit',
    Mode.addIgnore => 'Whole files: add, untrack, ignore or delete what is new or changed',
    Mode.history => 'The branches of a stack, in the order they merge',
    Mode.tasks => 'Backlog.md tasks and OpenSpec changes, Linear-style',
    Mode.repos => 'The repositories around you; pick the one the other modes work on',
    Mode.settings => 'Editors, terminals, the crawl depth and other preferences',
    Mode.log => 'What the actions and the crawl did',
    Mode.help => 'Every key the app has (?)',
  };

  IconData get icon => switch (this) {
    Mode.pullRequest => Icons.merge_type,
    Mode.changes => Icons.edit_note,
    Mode.addIgnore => Icons.playlist_add_check,
    Mode.history => Icons.account_tree_outlined,
    Mode.tasks => Icons.task_alt,
    Mode.repos => Icons.folder_outlined,
    Mode.settings => Icons.settings_outlined,
    Mode.log => Icons.receipt_long_outlined,
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
    this.cursor = false,
  });

  final IconData icon;
  final String label, tip;
  final bool selected;

  /// The rail has the keyboard and its cursor is on this entry.
  final bool cursor;
  final VoidCallback onTap;
}

/// The left rail: the expand/collapse toggle and one entry per mode. Collapsed: icons only, the
/// tooltip names the mode; expanded: labels, the tooltip explains the mode. The diff views of Pull
/// request and Changes are in the view bar above their panes (view_bar.dart).
class ModeRail extends StatelessWidget {
  const ModeRail({
    super.key,
    required this.mode,
    required this.expanded,
    this.cursor,
    this.toggleCursor = false,
    required this.onSelect,
    this.onStep,
    required this.onToggle,
  });

  final Mode mode;
  final bool expanded;

  /// The mode under the cursor while the rail has the keyboard; null otherwise.
  final Mode? cursor;

  /// The rail has the keyboard and its cursor is on the expand / collapse button.
  final bool toggleCursor;
  final ValueChanged<Mode> onSelect;

  /// The mouse wheel over the rail: -1 the previous mode, 1 the next (like Alt+[ and Alt+]).
  final ValueChanged<int>? onStep;
  final VoidCallback onToggle;

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
    for (final m in Mode.values)
      RailEntry(
        icon: m.icon,
        label: m.label,
        tip: expanded ? m.explain : m.label,
        selected: m == mode,
        cursor: m == cursor,
        onTap: () => onSelect(m),
      ),
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

  /// The width snaps to its new value: the rail sits in a Row with the mode area, an IndexedStack
  /// that lays out every mode, hidden ones too. A width animation (it was an AnimatedContainer)
  /// relaid all of them every frame of the slide and made the toggle crawl. Now the mode area is
  /// laid out once, and only the labels fade in (opacity: paint only, inside the rail's
  /// RepaintBoundary).
  Widget _body(List<RailEntry> entries) => RepaintBoundary(
    child: Container(
      width: expanded ? ModeRail.expandedWidth : ModeRail.collapsedWidth,
      color: C.surface,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4),
        itemCount: entries.length,
        itemBuilder: (context, i) => RailItem(entry: entries[i], expanded: expanded),
      ),
    ),
  );
}

class RailItem extends StatelessWidget {
  const RailItem({super.key, required this.entry, required this.expanded});

  final RailEntry entry;
  final bool expanded;

  /// Where the icon starts.
  static const double _indent = 13;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = e.selected || e.cursor ? C.text : C.muted;
    const left = _indent;
    return Tooltip(
      message: e.tip,
      child: InkWell(
        onTap: e.onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: left),
          decoration: BoxDecoration(
            color: e.cursor ? C.surface2 : null,
            border: Border(left: BorderSide(color: e.selected ? C.accent : Colors.transparent, width: 2)),
          ),
          child: Row(
            children: [
              Icon(e.icon, size: 20, color: color),
              if (expanded) const SizedBox(width: 10),
              if (expanded) Expanded(child: _Label(e.label, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.color});

  final String text;
  final Color color;

  /// The label fades in when the rail opens: an opacity change repaints the text and lays out nothing.
  static const fadeIn = Duration(milliseconds: 90);

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: fadeIn,
    builder: (context, v, child) => Opacity(opacity: v, child: child),
    child: Text(text, overflow: TextOverflow.ellipsis, softWrap: false, style: T.body.copyWith(color: color)),
  );
}
