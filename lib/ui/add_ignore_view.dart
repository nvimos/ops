import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../state/action_queue.dart';
import '../state/add_ignore.dart';
import '../backend/models.dart';
import '../local/file_manager.dart';
import '../state/ignore_pane.dart';
import '../state/prefs.dart';
import '../state/preview.dart';
import '../timing/ui_timing.dart';
import 'confirm_dialog.dart';
import 'error_view.dart';
import 'ignore_dialog.dart';
import 'ignore_pane.dart';
import 'key_sequence.dart';
import 'nav_keys.dart';
import 'path_cells.dart';
import 'preview_pane.dart';
import 'reveal.dart';
import 'side_pane.dart';
import 'theme.dart';
import 'widgets.dart';
import 'wheel_mode.dart';

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
  final _ignoreFilesFocus = FocusNode(debugLabel: 'ignore files');
  final _ignoreLinesFocus = FocusNode(debugLabel: 'ignore lines');
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
    'I': _hide,
    'p': () => _toggleSide(SideView.ignore),
    'v': () => _toggleSide(SideView.preview),
    'x': _delete,
    'r': () => st.store.refresh(),
  });

  AddIgnoreState get st => widget.state;

  IgnorePaneState? _ignorePane; // made when the pane first shows the rules
  PreviewState? _preview; // made when the pane first shows the preview

  /// The right-hand pane, as in Purrage: one view at a time, open on the remembered view until `p` or
  /// `v` hides it or shows the other.
  SideView _sideView = SideView.ignore;
  bool _sideOpen = true;

  /// The user chose open or closed with `p`, `v` or the switch: a later resize does not undo it.
  bool _sideChosen = false;

  /// Only [SidePane] listens: dragging the edge rebuilds neither the list nor the pane.
  final _sideWidth = ValueNotifier<double>(sidePaneDefaultWidth);
  Span? _resize;
  String _previewKey = '';

  /// Below this window width the side pane starts hidden; `p` or the switch still opens it.
  static const narrowWidth = 600.0;

  @override
  void initState() {
    super.initState();
    st.addListener(_onState);
    // The view and the width the user left behind, as in Purrage.
    final prefs = st.session.prefs;
    _sideView = prefs.text(Settings.sideViewKey) == 'preview' ? SideView.preview : SideView.ignore;
    _sideWidth.value = (prefs.number(Settings.sidePaneWidthKey) ?? sidePaneDefaultWidth.roundToDouble()).toDouble();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sideChosen) {
      final wide = MediaQuery.sizeOf(context).width >= narrowWidth;
      if (_sideOpen != wide) {
        _sideOpen = wide;
        _syncSide();
      }
    }
    _loadPreview();
  }

  @override
  void dispose() {
    st.removeListener(_onState);
    _preview?.dispose();
    _ignorePane?.dispose();
    _keys.dispose();
    focus.dispose();
    _filterFocus.dispose();
    _ignoreFilesFocus.dispose();
    _ignoreLinesFocus.dispose();
    _filter.dispose();
    _scroll.dispose();
    _sideWidth.dispose();
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

  /// `p` or `v`: show the pane on that view, or hide it when it already shows that view (Purrage's
  /// rule: one pane, the view remembered). [SidePane] shows the same switch above the pane.
  void _toggleSide(SideView view) {
    if (_sideOpen && _sideView == view) {
      _hideSide();
    } else {
      _showSide(view);
    }
  }

  /// The switch above the pane: open it on [view], keeping the view for next time.
  void _showSide(SideView view) {
    setState(() {
      _sideChosen = true;
      _sideOpen = true;
      if (_sideView != view) {
        _sideView = view;
        if (view == SideView.preview) _previewKey = ''; // a fresh preview when it comes back
      }
      // Remember the view the user last asked for, even when it already was the one shown.
      st.session.prefs.setText(Settings.sideViewKey, view.name);
    });
    _syncSide();
    _loadPreview();
  }

  void _hideSide() {
    setState(() {
      _sideChosen = true;
      _sideOpen = false;
    });
    _syncSide();
  }

  /// Tell the ignore panes whether they are on screen: hidden, they read nothing and mark themselves
  /// stale until shown again.
  void _syncSide() => _ignorePane?.setVisible(_sideOpen && _sideView == SideView.ignore);

  /// The pane's edge moved: draw it wider or narrower now; [done] saves the width.
  /// Each step is timed from the pointer event to the frame on screen (`addIgnore.resizeSide`).
  void _sizeSide(double width) {
    if (_resize == null) {
      final span = _resize = UiTiming.instance.span('addIgnore.resizeSide');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resize = null;
        span.markPainted();
      });
    }
    _sideWidth.value = width;
  }

  void _saveSideWidth() => st.session.prefs.setNumber(Settings.sidePaneWidthKey, _sideWidth.value.round());

  void _resetSideWidth() {
    _sideWidth.value = sidePaneDefaultWidth;
    _saveSideWidth();
  }

  void _onState() {
    _reveal();
    _loadPreview();
  }

  /// The preview follows the highlighted rows; it reads only when they change.
  void _loadPreview() {
    if (!_sideOpen || _sideView != SideView.preview) return;
    final paths = [for (final r in st.actionRows) r.path];
    final key = paths.join('|');
    if (key == _previewKey) return;
    _previewKey = key;
    final p = _preview ??= PreviewState(root: () => st.session.repo?.root ?? '.')..renderPdf = st.session.prefs.flag('previewPdf', fallback: false);
    p.load(paths);
  }

  Future<void> _launch(String file, {bool program = false}) async {
    try {
      await FileManager().launch(file, program: program);
    } on FileManagerException catch (e) {
      if (mounted) showActionError(context, '$e');
    }
  }

  /// The row's eye and `I`: ignore every highlighted row, and untrack the tracked ones too, so the
  /// file leaves the list (the rule goes into the project `.gitignore`; the file itself stays on
  /// disk).
  Future<void> _hide() async =>
      _report(await st.ignoreAndUntrackSelected(const IgnoreFileRef.gitignore('.gitignore')));

  /// Delete (the key or the menu): to the trash or for good, after asking only when Settings says so.
  Future<void> _delete() async {
    final rows = st.actionRows;
    if (rows.isEmpty) return;
    final permanent = !st.session.deleteToTrash;
    if (st.session.confirmDelete) {
      final what = rows.length == 1 ? rows.single.path : '${rows.length} files';
      final ok = await confirm(
        context,
        title: permanent ? 'Delete for good?' : 'Move to the trash?',
        text: permanent
            ? '$what is removed at once; there is no way back.'
            : '$what goes to the trash; a tracked file shows as deleted in Changes.',
        okLabel: permanent ? 'Delete for good' : 'Move to trash',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    _report(await st.deleteSelected());
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
    if (_ignoreFilesFocus.hasFocus) return _paneKey(e, atLines: false);
    if (_ignoreLinesFocus.hasFocus) return _paneKey(e, atLines: true);
    final hw = HardwareKeyboard.instance;
    final action = _action(e.logicalKey, hw);
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    // Ctrl + arrow jumps between the panes: the list, the ignore files, the lines.
    if (hw.isControlPressed) {
      if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
        _toIgnoreFiles();
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _toRail();
        return KeyEventResult.handled;
      }
    }
    // Shift + arrow extends the highlight; the other direction keys move (see nav_keys.dart).
    final nav = _keys.pending || hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed ? null : navKey(e);
    if (nav != null) {
      _navigate(e, nav, hw.isShiftPressed);
      return KeyEventResult.handled;
    }
    return _keys.press(e.character) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// The keys of the ignore file list ([atLines] false) and of the lines (true). They are two Tab
  /// stops; Right / `l` and Left / `h` move between the main list, the files and the lines.
  KeyEventResult _paneKey(KeyEvent e, {required bool atLines}) {
    final hw = HardwareKeyboard.instance;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.tab) {
      if (hw.isShiftPressed) {
        atLines ? _toIgnoreFiles() : focus.requestFocus();
      } else {
        atLines ? focus.requestFocus() : _toIgnoreLines();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      focus.requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      final pane = _ignorePane;
      if (pane == null) return KeyEventResult.handled;
      _runPaneEdit(atLines ? pane.openLine() : pane.openSelected());
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete && atLines) {
      final pane = _ignorePane;
      if (pane != null && pane.lineCursor > 0) _runPaneEdit(pane.deleteLine(pane.lineCursor));
      return KeyEventResult.handled;
    }
    final ch = e.character?.toLowerCase();
    if (ch == 'p' || ch == 'v') {
      _toggleSide(ch == 'p' ? SideView.ignore : SideView.preview);
      return KeyEventResult.handled;
    }
    if (hw.isControlPressed && (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight)) {
      if (k == LogicalKeyboardKey.arrowRight) {
        atLines ? null : _toIgnoreLines();
      } else {
        atLines ? _toIgnoreFiles() : focus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    final nav = navKey(e);
    if (nav == null) return KeyEventResult.ignored;
    if (nav.vertical) {
      final pane = _ignorePane;
      if (pane != null) {
        final step = nav.delta * (nav.big ? 10 : 1);
        atLines ? pane.moveLine(step) : pane.moveFile(step);
      }
      return KeyEventResult.handled;
    }
    if (nav.dir == NavDir.left) {
      atLines ? _toIgnoreFiles() : focus.requestFocus();
    } else if (!atLines) {
      _toIgnoreLines();
    }
    return KeyEventResult.handled;
  }

  void _toIgnoreFiles() {
    if (_sideOpen && _sideView == SideView.ignore) _ignoreFilesFocus.requestFocus();
  }

  /// Tab from the main list: the ignore file list when the ignore panes are shown, else the rail.
  void _tabForward() {
    if (_sideOpen && _sideView == SideView.ignore) {
      _toIgnoreFiles();
    } else {
      _toRail();
    }
  }

  void _toIgnoreLines() {
    if (_sideOpen && _sideView == SideView.ignore) _ignoreLinesFocus.requestFocus();
  }

  /// A line edit from the keyboard or the pane's own buttons: the same notice and Undo as its menu.
  Future<void> _runPaneEdit(Future<IgnoreEdit> edit) async {
    final result = await edit;
    if (!mounted) return;
    if (!result.ok) return showActionError(context, result.refusal);
    final undo = result.undo;
    if (undo == null) return;
    showAutoStatus(context, result.message!, onUndo: () async {
      final undone = await undo();
      if (mounted && !undone.ok) showActionError(context, undone.refusal);
    });
  }

  VoidCallback? _action(LogicalKeyboardKey k, HardwareKeyboard hw) => switch (k) {
    LogicalKeyboardKey.keyA when hw.isControlPressed => st.selectAll,
    LogicalKeyboardKey.keyD when hw.isControlPressed => () => st.move(10),
    LogicalKeyboardKey.keyU when hw.isControlPressed => () => st.move(-10),
    _ when hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed => null,
    LogicalKeyboardKey.space => st.toggleCursor,
    LogicalKeyboardKey.delete => _delete,
    LogicalKeyboardKey.slash => _filterFocus.requestFocus,
    LogicalKeyboardKey.tab => hw.isShiftPressed ? _filterFocus.requestFocus : _tabForward,
    LogicalKeyboardKey.escape when _filter.text.isNotEmpty => _clearFilter,
    LogicalKeyboardKey.escape => st.collapseSelection,
    _ => null,
  };

  void _navigate(KeyEvent e, NavKey nav, bool shift) {
    if (nav.dir == NavDir.left) return _toRail();
    if (nav.dir == NavDir.right) return _toIgnoreFiles();
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
        Expanded(child: RepaintBoundary(child: _listColumn())),
        if (_sideOpen)
          SidePane(
            width: _sideWidth,
            onWidth: _sizeSide,
            onDone: _saveSideWidth,
            onReset: _resetSideWidth,
            child: _sidePane(),
          ),
      ],
    ),
  );

  /// The one pane on the right: the ignore panes or the preview of the highlighted files, with a
  /// visible switch above them.
  Widget _sidePane() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SideSwitch(view: _sideView, onPick: _showSide, onHide: _hideSide),
      Expanded(
        child: _sideView == SideView.ignore
            ? IgnorePane(
                state: _ignorePane ??= IgnorePaneState(st),
                filesFocus: _ignoreFilesFocus,
                linesFocus: _ignoreLinesFocus,
                wheelStep: st.session.wheelStep,
              )
            : PreviewPane(
                state: _preview ??= PreviewState(root: () => st.session.repo?.root ?? '.')
                  ..renderPdf = st.session.prefs.flag('previewPdf', fallback: false),
                onLaunch: _launch,
              ),
      ),
    ],
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
          view: _sideOpen ? _sideView : null,
          onReload: st.store.refresh,
          onIgnoreView: () => _toggleSide(SideView.ignore),
          onPreviewView: () => _toggleSide(SideView.preview),
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
    return WheelMode(
      onStep: st.move,
      step: st.session.wheelStep,
      builder: (context, steps) => _List(
        rows: st.visible,
        cursor: st.cursor,
        controller: _scroll,
        scrolls: !steps,
        isSelected: st.isSelected,
        onTap: _tap,
        onAdd: (i) => _rowAction(i, _add),
        onUntrack: (i) => _rowAction(i, _untrack),
        onIgnore: (i) => _rowAction(i, _hide),
        onMenu: _menu,
      ),
    );
  }

  void _rowAction(int index, VoidCallback action) {
    _target(index);
    action();
  }

  /// Open the row in the editor Settings names (a folder opens as a folder).
  Future<void> _open(int index) async {
    if (index >= st.visible.length) return;
    final err = await st.openInEditor(st.visible[index].path);
    if (mounted) showActionError(context, err);
  }

  /// A right click on a row: act on it (or on the highlight when it is in it), then offer what can be
  /// done to it, as Purrage's Changes list did.
  Future<void> _menu(int index, Offset at) async {
    _target(index);
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<RowMenu>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
      items: rowMenuItems(permanent: !st.session.deleteToTrash),
    );
    if (!mounted) return;
    switch (choice) {
      case RowMenu.open:
        _open(index);
      case RowMenu.ignore:
        _ignoreDialog();
      case RowMenu.delete:
        _delete();
      case null:
        break;
    }
  }
}

/// What a row's right-click menu offers.
enum RowMenu { open, ignore, delete }

/// The right-click menu, as in Purrage: "Open" shows the file in the editor Settings names, "Ignore…"
/// opens the dialog that chooses a rule and its file, "Delete" sends the highlighted rows to the trash
/// (or removes them for good, as Settings says).
List<PopupMenuEntry<RowMenu>> rowMenuItems({required bool permanent}) => [
  const PopupMenuItem(
    value: RowMenu.open,
    height: 32,
    child: Tooltip(message: 'Open the row in the editor', child: Text('Open')),
  ),
  const PopupMenuItem(
    value: RowMenu.ignore,
    height: 32,
    child: Tooltip(message: 'Choose what to ignore and where the rule goes', child: Text('Ignore…')),
  ),
  PopupMenuItem(
    value: RowMenu.delete,
    height: 32,
    child: Tooltip(
      message: permanent
          ? 'Delete the highlighted rows for good: there is no way back'
          : 'Delete the highlighted rows: to the Recycle Bin on Windows, the Trash on macOS, '
                'removed for good on Linux',
      child: const Text('Delete'),
    ),
  ),
];

// Molecules and atoms -----------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.selected,
    required this.lit,
    required this.view,
    required this.onReload,
    required this.onIgnoreView,
    required this.onPreviewView,
  });

  final int count, selected;

  /// The list has the keyboard: its title is lit.
  final bool lit;

  /// The right-hand pane's view while it is open, or null when it is hidden.
  final SideView? view;
  final VoidCallback onReload, onIgnoreView, onPreviewView;

  @override
  Widget build(BuildContext context) => PaneHeader(
    title: Row(
      children: [
        Flexible(
          child: Text('Add and Ignore', overflow: TextOverflow.ellipsis, style: lit ? T.title : T.title.copyWith(color: C.muted)),
        ),
        const SizedBox(width: 8),
        Text(selected > 1 ? '$selected of $count selected' : '$count', style: T.tiny),
      ],
    ),
    trailing: [
      IconAction(
        icon: Icons.preview_outlined,
        tooltip: view == SideView.preview ? 'Hide the pane (v)' : 'Preview the highlighted files (v)',
        onPressed: onPreviewView,
        color: view == SideView.preview ? C.accent : C.muted,
      ),
      IconAction(
        icon: Icons.rule,
        tooltip: view == SideView.ignore ? 'Hide the pane (p)' : 'Show the ignore panes: .gitignore files and lines (p)',
        onPressed: onIgnoreView,
        color: view == SideView.ignore ? C.accent : C.muted,
      ),
      IconAction(icon: Icons.refresh, tooltip: 'Reload the list (r)', onPressed: onReload),
    ],
  );
}

/// The visible switch above the side pane: the ignore panes or the preview, remembered, and the
/// close button. The same views as `p` and `v`.
class _SideSwitch extends StatelessWidget {
  const _SideSwitch({required this.view, required this.onPick, required this.onHide});

  final SideView view;
  final ValueChanged<SideView> onPick;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: C.surface2,
      border: Border(bottom: BorderSide(color: C.border)),
    ),
    child: Row(
      children: [
        _SideTab(
          label: 'Ignore rules',
          icon: Icons.rule,
          chosen: view == SideView.ignore,
          tip: 'The .gitignore files and their lines (p)',
          onTap: () => onPick(SideView.ignore),
        ),
        const SizedBox(width: 6),
        _SideTab(
          label: 'Preview',
          icon: Icons.preview_outlined,
          chosen: view == SideView.preview,
          tip: 'The highlighted files (v)',
          onTap: () => onPick(SideView.preview),
        ),
        const Spacer(),
        IconAction(icon: Icons.close, tooltip: 'Hide the pane (p or v)', onPressed: onHide),
      ],
    ),
  );
}

class _SideTab extends StatelessWidget {
  const _SideTab({required this.label, required this.icon, required this.chosen, required this.tip, required this.onTap});

  final String label;
  final IconData icon;
  final bool chosen;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: SmallButton(label, icon: icon, primary: chosen, onPressed: onTap),
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
    required this.onMenu,
    this.scrolls = true,
  });

  final List<AddIgnoreRow> rows;
  final int cursor;
  final ScrollController controller;
  final bool Function(AddIgnoreRow) isSelected;
  final ValueChanged<int> onTap, onAdd, onUntrack, onIgnore;

  /// False while the wheel steps through the list: it must not scroll on its own then.
  final bool scrolls;

  /// A right click on a row, with where it happened.
  final void Function(int index, Offset at) onMenu;

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
      physics: scrolls ? null : const NeverScrollableScrollPhysics(),
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
          onMenu: (at) => onMenu(i, at),
        );
      },
    );
  }
}

String _sectionTitle(AddIgnoreSection s) => switch (s) {
  AddIgnoreSection.conflicts => 'Conflicts',
  AddIgnoreSection.staged => 'Staged',
  AddIgnoreSection.changed => 'Changed',
  AddIgnoreSection.untracked => 'Untracked',
};

/// The section heading above its rows, as in Purrage: `Staged (3)` in the section style, at the bottom
/// of its strip, close to its rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.section, this.count, {super.key});

  final AddIgnoreSection section;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Text('${_sectionTitle(section)} ($count)', style: T.section, maxLines: 1),
    ),
  );
}

/// What a row's letter says and its colour, as `git status -s` prints that side and colours it with
/// its defaults: the index side is green (`color.status.added` / `updated`), the worktree side is
/// red (`changed`), and an untracked or unmerged path is red too. The theme's greens and reds are
/// muted so the letters sit in the dark sheet instead of glowing like a terminal.
(String, Color) _kind(AddIgnoreRow row) {
  final file = row.file;
  if (row.conflicted) {
    final code = file.index.trim().isEmpty ? file.worktree.trim() : file.index.trim();
    return (code.isEmpty ? 'U' : code, C.red);
  }
  if (row.untracked) return ('?', C.red);
  final staged = row.section == AddIgnoreSection.staged;
  final code = (staged ? file.index : file.worktree).trim();
  if (code.isEmpty) return ('M', staged ? C.green : C.red);
  return (code, staged ? C.green : C.red);
}

/// What the row's letter means on its side, for the hover tooltip.
String _kindTip(AddIgnoreRow row, String letter) {
  if (row.conflicted) return 'Unmerged: a conflict is waiting to be resolved';
  if (row.untracked) return 'Untracked: git does not track this path yet';
  final what = switch (letter) {
    'A' => 'Added',
    'D' => 'Deleted',
    'R' => 'Renamed',
    'C' => 'Copied',
    'T' => 'Type changed',
    _ => 'Modified',
  };
  return row.section == AddIgnoreSection.staged
      ? '$what: staged in the index, ready to commit'
      : '$what: in the working tree, not staged yet';
}

/// One whole-file row: the kind of change, the folder, the actions in their fixed slot, then the name,
/// as in Purrage. The columns are top-level children of the row, so every row's folder ends and name
/// starts at the same place.
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
    required this.onMenu,
  });

  final AddIgnoreRow row;

  /// The keyboard cursor is on this row.
  final bool cursor;

  /// The row is highlighted (part of the selection).
  final bool selected;
  final VoidCallback onTap, onAdd, onUntrack, onIgnore;

  /// A right click, with where it happened.
  final ValueChanged<Offset> onMenu;

  /// The room the row's buttons take (three 21 px icons: add, untrack, ignore), so the name column
  /// stays put whatever a row shows and whether the mouse is on it.
  static const double actionsWidth = 63;

  @override
  Widget build(BuildContext context) {
    final (letter, color) = _kind(row);
    return HoverRow(
      selected: selected || cursor,
      pointer: false, // a click on a file row is obvious (the file lists keep the plain cursor)
      onTap: onTap,
      onContextMenu: onMenu,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: addIgnoreRowHeight,
        child: Row(
          children: [
            Tooltip(
              message: _kindTip(row, letter),
              child: SizedBox(width: 18, child: Text(letter, style: T.small.copyWith(color: color, fontWeight: FontWeight.w600))),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: PathFolder(row.folder)),
            const SizedBox(width: 8),
            SizedBox(width: actionsWidth, child: _Actions(row: row, onAdd: onAdd, onUntrack: onUntrack, onIgnore: onIgnore)),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: PathName(row.name, color: row.isDirectory ? C.folder : null)),
          ],
        ),
      ),
    );
  }
}

/// The row's buttons, always there: add or untrack, then the eye that ignores the row (and stops
/// tracking it when it is tracked, so the file goes away). Delete is in the right-click menu, as in
/// Purrage.
class _Actions extends StatelessWidget {
  const _Actions({required this.row, required this.onAdd, required this.onUntrack, required this.onIgnore});

  final AddIgnoreRow row;
  final VoidCallback onAdd, onUntrack, onIgnore;

  @override
  Widget build(BuildContext context) {
    final staged = row.section == AddIgnoreSection.staged;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!staged && !row.conflicted) IconAction(icon: Icons.add, tooltip: 'Add: stage the whole file (t)', onPressed: onAdd),
        if (row.section != AddIgnoreSection.untracked && !row.conflicted)
          IconAction(icon: Icons.remove, tooltip: 'Untrack: take it out of the index (u)', onPressed: onUntrack),
        if (!row.conflicted)
          IconAction(
            icon: Icons.visibility_off_outlined,
            tooltip: row.untracked
                ? 'Ignore: add the literal path to the project .gitignore (I; i or right-click to choose)'
                : 'Ignore and untrack: add the literal path to the project .gitignore and stop tracking it, '
                      'so it leaves the list (I; i or right-click to choose)',
            onPressed: onIgnore,
          ),
      ],
    );
  }
}
