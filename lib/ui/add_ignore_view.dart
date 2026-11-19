import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../state/action_queue.dart';
import '../state/add_ignore.dart';
import '../state/changes.dart' show fileKind;
import '../state/ignore_pane.dart';
import 'confirm_dialog.dart';
import 'error_view.dart';
import 'ignore_dialog.dart';
import 'ignore_pane.dart';
import 'key_sequence.dart';
import 'nav_keys.dart';
import 'reveal.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Add and Ignore mode: every changed or untracked path as one whole-file row, in sections
/// (conflicts, staged, changed, untracked), with a filter, a selection and the row actions add,
/// untrack, ignore and delete. Whole files only; hunks and the diff stay in Changes.
///
/// Page: owns keys and event handlers; [AddIgnoreState] does the work.
class AddIgnoreView extends StatefulWidget {
  const AddIgnoreView({super.key, required this.state, this.onRail});

  final AddIgnoreState state;

  /// Gives the keyboard to the mode rail (Left, Tab round the cycle).
  final VoidCallback? onRail;

  @override
  State<AddIgnoreView> createState() => AddIgnoreViewState();
}

/// Heights of the list items; every row and header has one, so a row's top follows from its index.
const double addIgnoreRowHeight = 30;
const double addIgnoreHeaderHeight = 28;

class AddIgnoreViewState extends State<AddIgnoreView> {
  final focus = FocusNode(debugLabel: 'add and ignore');
  final _filterFocus = FocusNode(debugLabel: 'add and ignore filter');
  final _filter = TextEditingController();
  final _scroll = ScrollController();
  static const _far = 1 << 20;

  late final _keys = KeySequence({
    '{': () => st.move(-3),
    '}': () => st.move(3),
    'gg': () => st.move(-_far),
    'G': () => st.move(_far),
    'gi': focusFilter,
    't': _add,
    'u': _untrack,
    'i': _ignoreDialog,
    'I': _ignore,
    'p': _togglePane,
    'x': _delete,
    'r': () => st.store.refresh(),
  });

  AddIgnoreState get st => widget.state;

  IgnorePaneState? _ignorePane; // made when the pane is first opened
  bool _paneOpen = false;

  @override
  void initState() {
    super.initState();
    st.addListener(_reveal);
  }

  @override
  void dispose() {
    st.removeListener(_reveal);
    _ignorePane?.dispose();
    _keys.dispose();
    focus.dispose();
    _filterFocus.dispose();
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toRail() => widget.onRail?.call();

  /// Tab from the rail: the filter; Shift+Tab from the rail: the list.
  void enterFromRail({required bool forward}) => forward ? focusFilter() : focus.requestFocus();

  void focusFilter() => _filterFocus.requestFocus();

  /// The list keeps the cursor row in view: its top follows from its index (fixed heights).
  void _reveal() {
    if (st.visible.isEmpty) return;
    final top = st.headersAbove(st.cursor) * addIgnoreHeaderHeight + st.cursor * addIgnoreRowHeight;
    revealRange(_scroll, top, addIgnoreRowHeight);
  }

  // Event handlers -------------------------------------------------------------------------------

  void _report(ActionResult r) {
    if (mounted) showActionError(context, r.error == 'nothing to add' ? null : r.error);
  }

  Future<void> _add() async => _report(await st.trackSelected());

  Future<void> _untrack() async => _report(await st.untrackSelected());

  /// i: ask what to ignore (the file, its kind, its folder) and where to write the rule.
  Future<void> _ignoreDialog() => showIgnoreDialog(context, st);

  void _togglePane() => setState(() => _paneOpen = !_paneOpen);

  /// I: a rule for each untracked highlighted row into the repository's root `.gitignore`, no questions.
  Future<void> _ignore() async {
    final target = st.rootIgnore;
    if (target == null) return _report(const ActionResult('ignore', 'ignore needs a local repository'));
    _report(await st.ignoreSelected(target));
  }

  Future<void> _delete() async {
    final rows = st.actionRows;
    if (rows.isEmpty) return;
    final what = rows.length == 1 ? rows.single.path : '${rows.length} files';
    final ok = await confirm(
      context,
      title: 'Move to the trash?',
      text: '$what goes to the trash; a tracked file shows as deleted in Changes.',
      okLabel: 'Move to trash',
      danger: true,
    );
    if (ok && mounted) _report(await st.deleteSelected());
  }

  void _tap(int index) {
    final hw = HardwareKeyboard.instance;
    focus.requestFocus();
    st.click(index, ctrl: hw.isControlPressed || hw.isMetaPressed, shift: hw.isShiftPressed);
  }

  /// A right-click or the row's own buttons act on the row, or on the highlighted rows when it
  /// is one of them.
  void _target(int index) {
    final row = st.visible[index];
    if (!st.isSelected(row)) st.click(index);
    focus.requestFocus();
  }

  void _clearFilter() {
    _filter.clear();
    st.setFilter('');
  }

  // Keys ---------------------------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_filterFocus.hasFocus) return _filterKey(e.logicalKey);
    final hw = HardwareKeyboard.instance;
    final action = _action(e.logicalKey, hw);
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    // Shift + arrow extends the highlight; the other direction keys move (see nav_keys.dart).
    final nav = _keys.pending || hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed ? null : navKey(e);
    if (nav != null) {
      _navigate(e, nav, hw.isShiftPressed);
      return KeyEventResult.handled;
    }
    return _keys.press(e.character) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  VoidCallback? _action(LogicalKeyboardKey k, HardwareKeyboard hw) => switch (k) {
    LogicalKeyboardKey.keyA when hw.isControlPressed => st.selectAll,
    LogicalKeyboardKey.keyD when hw.isControlPressed => () => st.move(10),
    LogicalKeyboardKey.keyU when hw.isControlPressed => () => st.move(-10),
    _ when hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed => null,
    LogicalKeyboardKey.space => st.toggleCursor,
    LogicalKeyboardKey.delete => _delete,
    LogicalKeyboardKey.slash => _filterFocus.requestFocus,
    LogicalKeyboardKey.tab => hw.isShiftPressed ? _filterFocus.requestFocus : _toRail,
    LogicalKeyboardKey.escape when _filter.text.isNotEmpty => _clearFilter,
    LogicalKeyboardKey.escape => st.collapseSelection,
    _ => null,
  };

  void _navigate(KeyEvent e, NavKey nav, bool shift) {
    if (nav.dir == NavDir.left) return _toRail();
    if (!nav.vertical) return;
    final arrow = e.logicalKey == LogicalKeyboardKey.arrowUp || e.logicalKey == LogicalKeyboardKey.arrowDown;
    if (shift && arrow) return st.extend(nav.delta);
    st.move(nav.delta * (nav.big ? 10 : 1));
  }

  /// In the filter: Esc, Tab or arrow down go back to the list.
  KeyEventResult _filterKey(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.tab && HardwareKeyboard.instance.isShiftPressed) {
      _toRail();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft && !HardwareKeyboard.instance.isShiftPressed && cursorAtStart(_filter)) {
      _toRail();
      return KeyEventResult.handled;
    }
    const back = [LogicalKeyboardKey.escape, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.tab, LogicalKeyboardKey.enter];
    if (!back.contains(k)) return KeyEventResult.ignored;
    focus.requestFocus();
    return KeyEventResult.handled;
  }

  // Layout -------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onKeyEvent: _onKey,
    child: Row(
      children: [
        Expanded(child: _listColumn()),
        if (_paneOpen) ...[
          const VerticalDivider(width: 1),
          SizedBox(width: 340, child: IgnorePane(state: _ignorePane ??= IgnorePaneState(st))),
        ],
      ],
    ),
  );

  Widget _listColumn() => ListenableBuilder(
    listenable: Listenable.merge([st, focus]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          count: st.rows.length,
          selected: st.selectionCount,
          lit: focus.hasFocus,
          paneOpen: _paneOpen,
          onReload: st.store.refresh,
          onPane: _togglePane,
        ),
        _Filter(controller: _filter, focus: _filterFocus, onChanged: st.setFilter),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _body() {
    if (st.store.error != null) return ErrorPane(st.store.error!, onRetry: st.store.refresh);
    if (st.store.status == null) return const Empty('Loading…');
    if (st.rows.isEmpty) return const Empty('Nothing to add or ignore: the working tree is clean.');
    if (st.visible.isEmpty) return Empty('No path matches "${st.filter}".');
    return _List(
      rows: st.visible,
      cursor: st.cursor,
      controller: _scroll,
      isSelected: st.isSelected,
      onTap: _tap,
      onAdd: (i) => _rowAction(i, _add),
      onUntrack: (i) => _rowAction(i, _untrack),
      onIgnore: (i) => _rowAction(i, _ignore),
      onDelete: (i) => _rowAction(i, _delete),
    );
  }

  void _rowAction(int index, VoidCallback action) {
    _target(index);
    action();
  }
}

// Molecules and atoms -----------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.selected,
    required this.lit,
    required this.paneOpen,
    required this.onReload,
    required this.onPane,
  });

  final int count, selected;

  /// The list has the keyboard: its title is lit.
  final bool lit;
  final bool paneOpen;
  final VoidCallback onReload, onPane;

  @override
  Widget build(BuildContext context) => PaneHeader(
    title: Row(
      children: [
        Text('Add and Ignore', style: lit ? T.title : T.title.copyWith(color: C.muted)),
        const SizedBox(width: 8),
        Text(selected > 1 ? '$selected of $count selected' : '$count', style: T.tiny),
      ],
    ),
    trailing: [
      IconAction(
        icon: Icons.rule,
        tooltip: paneOpen ? 'Hide the ignore rules (p)' : 'Show the ignore rules around the cursor row (p)',
        onPressed: onPane,
        color: paneOpen ? C.accent : C.muted,
      ),
      IconAction(icon: Icons.refresh, tooltip: 'Reload the list (r)', onPressed: onReload),
    ],
  );
}

class _Filter extends StatelessWidget {
  const _Filter({required this.controller, required this.focus, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: ClearOnAltX(
      controller: controller,
      onCleared: onChanged,
      child: TextField(
        controller: controller,
        focusNode: focus,
        style: T.body,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 15, color: C.muted),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          suffixIcon: ClearButton(controller: controller, onCleared: onChanged),
          suffixIconConstraints: ClearButton.constraints,
          hintText: 'Filter (/)',
        ),
        onChanged: onChanged,
      ),
    ),
  );
}

/// The rows with a header above the first row of each section.
class _List extends StatelessWidget {
  const _List({
    required this.rows,
    required this.cursor,
    required this.controller,
    required this.isSelected,
    required this.onTap,
    required this.onAdd,
    required this.onUntrack,
    required this.onIgnore,
    required this.onDelete,
  });

  final List<AddIgnoreRow> rows;
  final int cursor;
  final ScrollController controller;
  final bool Function(AddIgnoreRow) isSelected;
  final ValueChanged<int> onTap, onAdd, onUntrack, onIgnore, onDelete;

  /// The list items: a header (section) before the first row of each section, else a row index.
  List<({AddIgnoreSection? header, int row})> get _items {
    final out = <({AddIgnoreSection? header, int row})>[];
    AddIgnoreSection? last;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].section != last) out.add((header: rows[i].section, row: -1));
      last = rows[i].section;
      out.add((header: null, row: i));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return ListView.builder(
      controller: controller,
      itemCount: items.length,
      itemExtentBuilder: (at, _) => items[at].header == null ? addIgnoreRowHeight : addIgnoreHeaderHeight,
      itemBuilder: (context, at) {
        final item = items[at];
        if (item.header != null) return SectionHeader(item.header!, rows.where((r) => r.section == item.header).length);
        final i = item.row;
        return AddIgnoreRowTile(
          row: rows[i],
          cursor: i == cursor,
          selected: isSelected(rows[i]),
          onTap: () => onTap(i),
          onAdd: () => onAdd(i),
          onUntrack: () => onUntrack(i),
          onIgnore: () => onIgnore(i),
          onDelete: () => onDelete(i),
        );
      },
    );
  }
}

String _sectionTitle(AddIgnoreSection s) => switch (s) {
  AddIgnoreSection.conflicts => 'CONFLICTS',
  AddIgnoreSection.staged => 'STAGED',
  AddIgnoreSection.changed => 'CHANGED',
  AddIgnoreSection.untracked => 'UNTRACKED',
};

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.section, this.count, {super.key});

  final AddIgnoreSection section;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
    child: Text('${_sectionTitle(section)}  $count', style: T.section),
  );
}

/// What a row's letter says and its colour: the kind of change on that side.
(String, Color) _kind(AddIgnoreRow row) {
  final staged = row.section == AddIgnoreSection.staged;
  return switch (fileKind(row.file, staged: staged)) {
    'conflicted' => ('!', C.yellow),
    'untracked' => ('?', C.muted),
    'added' => ('A', C.green),
    'deleted' => ('D', C.red),
    'renamed' => ('R', C.accent),
    _ => ('M', C.yellow),
  };
}

/// One whole-file row: the kind of change, the name, its folder, and the actions on hover.
class AddIgnoreRowTile extends StatelessWidget {
  const AddIgnoreRowTile({
    super.key,
    required this.row,
    required this.cursor,
    required this.selected,
    required this.onTap,
    required this.onAdd,
    required this.onUntrack,
    required this.onIgnore,
    required this.onDelete,
  });

  final AddIgnoreRow row;

  /// The keyboard cursor is on this row.
  final bool cursor;

  /// The row is highlighted (part of the selection).
  final bool selected;
  final VoidCallback onTap, onAdd, onUntrack, onIgnore, onDelete;

  @override
  Widget build(BuildContext context) {
    final (letter, color) = _kind(row);
    return HoverRow(
      selected: selected || cursor,
      pointer: false, // a click on a file row is obvious (the file lists keep the plain cursor)
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: addIgnoreRowHeight,
        child: Row(
          children: [
            SizedBox(width: 18, child: Text(letter, style: T.small.copyWith(color: color, fontWeight: FontWeight.w600))),
            Text(row.name, style: T.body),
            const SizedBox(width: 8),
            Expanded(child: Text(row.folder, style: T.tiny, overflow: TextOverflow.ellipsis)),
            _Actions(row: row, onAdd: onAdd, onUntrack: onUntrack, onIgnore: onIgnore, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}

/// The row's buttons, shown while the mouse is over the row (always on touch).
class _Actions extends StatelessWidget {
  const _Actions({required this.row, required this.onAdd, required this.onUntrack, required this.onIgnore, required this.onDelete});

  final AddIgnoreRow row;
  final VoidCallback onAdd, onUntrack, onIgnore, onDelete;

  @override
  Widget build(BuildContext context) {
    if (!RowHover.of(context)) return const SizedBox.shrink();
    final staged = row.section == AddIgnoreSection.staged;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!staged && !row.conflicted) IconAction(icon: Icons.add, tooltip: 'Add: stage the whole file (t)', onPressed: onAdd),
        if (row.section != AddIgnoreSection.untracked && !row.conflicted)
          IconAction(icon: Icons.remove, tooltip: 'Untrack: take it out of the index (u)', onPressed: onUntrack),
        if (row.untracked) IconAction(icon: Icons.visibility_off_outlined, tooltip: 'Ignore: add a rule to .gitignore (i)', onPressed: onIgnore),
        if (!row.conflicted) IconAction(icon: Icons.delete_outline, tooltip: 'Delete: move to the trash (x)', onPressed: onDelete, color: C.yellow),
      ],
    );
  }
}
