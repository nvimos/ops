import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../state/prefs.dart';
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

/// The rail's arrangement, kept in [Prefs]: the order of the modes and the ones the user hid.
///
/// The order holds every mode, hidden ones included, so a mode that is shown again returns to the
/// place it was dragged to. A drag reorders the shown entries and leaves the hidden slots alone.
class RailState extends ChangeNotifier {
  RailState(this._prefs) {
    _repair();
  }

  final Prefs _prefs;

  static const orderKey = 'modeOrder';
  static const hiddenKey = 'hiddenModes';

  static Mode? _parse(String name) {
    for (final m in Mode.values) {
      if (m.name == name) return m;
    }
    return null;
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Keeps the saved state usable: names that no longer exist (a mode was renamed or removed) are
  /// dropped, duplicates go, a mode added since the save comes last, and a hidden set that would
  /// hide every mode is forgotten. Repaired once, only when something changed.
  void _repair() {
    final full = order; // already drops unknown names, dedupes and appends the new modes
    final savedOrder = _prefs.strings(orderKey);
    final cleanOrder = [for (final m in full) m.name];
    if (!_same(savedOrder, cleanOrder)) _write(orderKey, cleanOrder);

    final known = {for (final m in Mode.values) m.name};
    final seen = <String>[];
    for (final name in _prefs.strings(hiddenKey)) {
      if (known.contains(name) && !seen.contains(name)) seen.add(name);
    }
    final cleanHidden = [for (final m in full) if (seen.contains(m.name)) m.name];
    final usable = cleanHidden.length >= Mode.values.length ? <String>[] : cleanHidden;
    if (!_same(_prefs.strings(hiddenKey), usable)) _write(hiddenKey, usable);
  }

  // The parsed order, hidden set and visible list, built once per change of the saved prefs (the
  // shell reads them many times per build and key). Every write goes through [_write], which drops
  // them. Unmodifiable, so no caller can edit the cache.
  List<Mode>? _order, _visible;
  Set<Mode>? _hidden;

  void _write(String key, List<String> value) {
    _prefs.setStrings(key, value);
    _order = _visible = null;
    _hidden = null;
  }

  /// Every mode, in rail order. Modes added since the order was saved come last, in enum order.
  List<Mode> get order => _order ??= List.unmodifiable(_parseOrder());

  List<Mode> _parseOrder() {
    final out = <Mode>[];
    for (final name in _prefs.strings(orderKey)) {
      final m = _parse(name);
      if (m != null && !out.contains(m)) out.add(m);
    }
    for (final m in Mode.values) {
      if (!out.contains(m)) out.add(m);
    }
    return out;
  }

  Set<Mode> get hidden => _hidden ??= Set.unmodifiable(_parseHidden());

  Set<Mode> _parseHidden() {
    final out = <Mode>{};
    for (final name in _prefs.strings(hiddenKey)) {
      final m = _parse(name);
      if (m != null) out.add(m);
    }
    // A save from a version with fewer modes can hide every mode that still exists: forget it,
    // rather than leave the app with no visible mode.
    return out.length >= Mode.values.length ? {} : out;
  }

  /// The entries the rail shows, in order. Never empty.
  List<Mode> get visible => _visible ??= _shown();

  List<Mode> _shown() {
    final blocked = hidden;
    final shown = [for (final m in order) if (!blocked.contains(m)) m];
    return shown.isEmpty ? order : List.unmodifiable(shown);
  }

  /// The last visible mode cannot be hidden: the app always has a mode to show.
  bool get canHide => visible.length > 1;

  /// Move the shown entry [oldIndex] to [newIndex] (both in [visible]); hidden modes keep their
  /// place in the full order. Bad indices from a stale drag do nothing.
  void reorderVisible(int oldIndex, int newIndex) {
    final shown = [...visible];
    if (oldIndex < 0 || oldIndex >= shown.length || newIndex < 0 || newIndex >= shown.length) return;
    shown.insert(newIndex, shown.removeAt(oldIndex));
    var i = 0;
    final hiddenNow = hidden;
    final full = [for (final m in order) hiddenNow.contains(m) ? m : shown[i++]];
    _write(orderKey, [for (final m in full) m.name]);
    notifyListeners();
  }

  /// Right click on a rail icon: take the mode off the rail. False when it is the last one.
  bool hide(Mode mode) {
    if (!canHide || hidden.contains(mode)) return false;
    final next = {...hidden, mode};
    _write(hiddenKey, [for (final m in order) if (next.contains(m)) m.name]);
    notifyListeners();
    return true;
  }

  /// Settings: put a hidden mode back where it was in the rail.
  void show(Mode mode) {
    if (!hidden.contains(mode)) return;
    final next = {...hidden}..remove(mode);
    _write(hiddenKey, [for (final m in order) if (next.contains(m)) m.name]);
    notifyListeners();
  }
}

/// One entry of the rail.
class RailEntry {
  const RailEntry({
    required this.icon,
    required this.label,
    required this.tip,
    required this.selected,
    required this.onTap,
    this.mode,
    this.cursor = false,
  });

  final IconData icon;
  final String label, tip;
  final bool selected;

  /// The mode this entry opens; null for the expand / collapse button.
  final Mode? mode;

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
    this.modes = Mode.values,
    required this.expanded,
    this.cursor,
    this.toggleCursor = false,
    required this.onSelect,
    this.onStep,
    required this.onToggle,
    this.onReorder,
    this.onHide,
  });

  final Mode mode;

  /// The modes to show, in rail order (the hidden ones are already left out).
  final List<Mode> modes;
  final bool expanded;

  /// The mode under the cursor while the rail has the keyboard; null otherwise.
  final Mode? cursor;

  /// The rail has the keyboard and its cursor is on the expand / collapse button.
  final bool toggleCursor;
  final ValueChanged<Mode> onSelect;

  /// The mouse wheel over the rail: -1 the previous mode, 1 the next (like Alt+[ and Alt+]).
  final ValueChanged<int>? onStep;
  final VoidCallback onToggle;

  /// A mode was dragged onto the entry at [newIndex] (both indices in [modes]); null: no dragging.
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// The right-click menu's Hide; null: no menu.
  final ValueChanged<Mode>? onHide;

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
    for (final m in modes)
      RailEntry(
        icon: m.icon,
        label: m.label,
        tip: expanded ? m.explain : m.label,
        selected: m == mode,
        mode: m,
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
        itemBuilder: (context, i) => _item(context, i, entries[i]),
      ),
    ),
  );

  /// One rail row: the toggle as it is, a mode row as a drag source and a drop target.
  Widget _item(BuildContext context, int index, RailEntry entry) {
    final mode = entry.mode;
    final item = RailItem(
      entry: entry,
      expanded: expanded,
      onMenu: mode == null || onHide == null ? null : (at) => _menu(context, mode, at),
    );
    if (mode == null || onReorder == null) return item;
    return Draggable<Mode>(
      data: mode,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _feedback(mode),
      childWhenDragging: Opacity(opacity: .35, child: item),
      child: DragTarget<Mode>(
        onWillAcceptWithDetails: (d) => d.data != mode,
        onAcceptWithDetails: (d) {
          // Look the mode up again: a hide or unhide during the drag may have shifted the indices.
          final from = modes.indexOf(d.data);
          if (from >= 0) onReorder!(from, index - 1);
        },
        builder: (context, candidate, _) => DecoratedBox(
          decoration: BoxDecoration(border: _dropLine(candidate, index - 1)),
          child: item,
        ),
      ),
    );
  }

  /// Where the dragged mode will land: the dropped entry takes the target's place, so a mode from
  /// above lands below the target (line at the bottom) and one from below lands above it (top).
  Border _dropLine(List<Mode?> candidate, int target) {
    const none = BorderSide(color: Colors.transparent, width: 2);
    final dragged = candidate.isEmpty ? null : candidate.first;
    if (dragged == null) return const Border(top: none, bottom: none);
    const line = BorderSide(color: C.accent, width: 2);
    final down = modes.indexOf(dragged) < target;
    return Border(top: down ? none : line, bottom: down ? line : none);
  }

  /// What follows the pointer while a mode is dragged: the icon, and the label when the rail is open.
  Widget _feedback(Mode mode) => Material(
    color: Colors.transparent,
    child: Container(
      width: expanded ? expandedWidth : collapsedWidth,
      height: 44,
      decoration: BoxDecoration(color: C.surface2, border: Border.all(color: C.accent)),
      child: Row(
        children: [
          const SizedBox(width: RailItem._indent),
          Icon(mode.icon, size: 20, color: C.text),
          if (expanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(mode.label, style: T.body, overflow: TextOverflow.ellipsis, softWrap: false),
            ),
          ],
        ],
      ),
    ),
  );

  /// A right click on a mode: take it off the rail. The last visible mode has no menu.
  Future<void> _menu(BuildContext context, Mode mode, Offset at) async {
    if (onHide == null || modes.length <= 1) return;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) return;
    final hide = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          value: true,
          height: 32,
          child: Tooltip(
            message: 'Take ${mode.label} off the rail; Settings shows it again',
            child: Text('Hide ${mode.label}'),
          ),
        ),
      ],
    );
    if (hide == true && context.mounted) onHide!(mode);
  }
}

class RailItem extends StatelessWidget {
  const RailItem({super.key, required this.entry, required this.expanded, this.onMenu});

  final RailEntry entry;
  final bool expanded;

  /// A right click, with where it happened (screen coordinates); null: no menu.
  final ValueChanged<Offset>? onMenu;

  /// Where the icon starts.
  static const double _indent = 13;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = e.selected || e.cursor ? C.text : C.muted;
    const left = _indent;
    final row = InkWell(
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
    );
    return Tooltip(
      message: e.tip,
      child: onMenu == null
          ? row
          : GestureDetector(onSecondaryTapUp: (d) => onMenu!(d.globalPosition), child: row),
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
