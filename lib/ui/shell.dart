import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../state/dirs.dart';
import '../state/pr.dart';
import '../state/session.dart';
import '../tasks/model.dart';
import '../tasks/workspace.dart';
import 'changes_view.dart';
import 'connect.dart';
import 'dirs_view.dart';
import 'error_view.dart';
import 'key_sequence.dart';
import 'nav_keys.dart';
import 'help_view.dart';
import 'debug_bar.dart';
import 'mode_rail.dart';
import 'pr_view.dart';
import 'status_bar.dart';
import 'tasks/tasks_view.dart';

export 'mode_rail.dart' show Mode;

/// The window: the mode rail, the modes (kept alive), the status bar. Owns the app-wide keys
/// and which mode has the keyboard.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Mode _mode = Mode.pullRequest;
  bool _expanded = false;
  PrState? _pr;
  Workspace? _ws;
  DirsState? _dirs;
  final _focus = FocusNode(debugLabel: 'shell');

  /// The task whose branch the Pull request view is reviewing (its Verify list shows beside it).
  Task? _reviewing;
  final _tasksKey = GlobalKey<TasksViewState>();
  final _changesKey = GlobalKey<ChangesViewState>();
  final _dirsKey = GlobalKey<DirsViewState>();
  final _helpKey = GlobalKey<HelpViewState>();

  /// The mode rail takes the keyboard (Left from the leftmost pane, Tab round the cycle); its cursor
  /// starts on the current mode.
  final _railFocus = FocusNode(debugLabel: 'rail');

  /// The rail cursor: 0 is the expand / collapse button, 1.. are the modes in rail order.
  int _railCursor = 1;
  late final _prKeys = KeySequence({
    'v': () => _pr?.toggleLayout(),
    'i': () => _pr?.baseFocus.requestFocus(), // input: the base picker
    'gi': () => _pr?.baseFocus.requestFocus(), // go input: the base picker
    '2gi': () => _pr?.headFocus.requestFocus(), // the head picker
    'gs': () => _pr?.swap(),
    ']f': () => _pr?.selectNext(1),
    '[f': () => _pr?.selectNext(-1),
    'zw': () => _pr?.toggleWrap(),
    'zh': () => _pr?.toggleHunkHeaders(),
    'zR': () => _pr?.expandAllDirs(),
    'zM': () => _pr?.collapseAllDirs(),
    '{': () => _pr?.jump(-1),
    '}': () => _pr?.jump(1),
    'gg': () => _pr?.moveCursor(-_far),
    'G': () => _pr?.moveCursor(_far),
    ']c': () => _pr?.moveHunk(1),
    '[c': () => _pr?.moveHunk(-1),
    'zc': () => _pr?.foldSelected(fold: true),
    'zo': () => _pr?.foldSelected(fold: false),
    'o': _openPr,
  });

  /// Far enough to reach the first or last item of any list.
  static const _far = 1 << 20;

  @override
  void dispose() {
    _prKeys.dispose();
    _focus.dispose();
    _railFocus.dispose();
    _pr?.dispose();
    _ws?.dispose();
    _dirs?.dispose();
    super.dispose();
  }

  // Event handlers -------------------------------------------------------------------------------

  void _openTask(String id) {
    _setMode(Mode.tasks);
    _tasksKey.currentState?.openTask(id);
  }

  void _review(Task t, String branch) {
    setState(() => _reviewing = t);
    _setMode(Mode.pullRequest);
    _pr!.pick(base: _ws!.defaultBranch, head: branch);
  }

  void _stopReview() => setState(() => _reviewing = null);

  void _toggleRail() => setState(() => _expanded = !_expanded);

  void _setLayout(DiffLayout l) => SessionScope.read(context).diffPrefs.setLayout(l);

  /// Switch modes and give the keyboard to the new one (Tasks and Directories have their own keys).
  void _setMode(Mode m) {
    setState(() => _mode = m);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusMode(m));
  }

  void _focusMode(Mode m) => switch (m) {
    Mode.changes => _changesKey.currentState?.focus.requestFocus(),
    Mode.tasks => _tasksKey.currentState?.focus.requestFocus(),
    Mode.directories => _dirsKey.currentState?.focusFilter(),
    _ => _focus.requestFocus(),
  };

  /// Shift+C: the Changes mode, with the branch switcher focused and its list open.
  void _openBranchSwitcher() {
    _setMode(Mode.changes);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changesKey.currentState?.openBranchSwitcher());
  }

  void _stepMode(int delta) => _setMode(Mode.values[(_mode.index + delta) % Mode.values.length]);

  // Keys -----------------------------------------------------------------------------------------

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];

  /// A text field has the keyboard: plain keys are typing, not commands.
  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    final handled = switch (e.logicalKey) {
      // App-wide, also while typing.
      final k when hw.isAltPressed && !hw.isControlPressed => _altKey(k),
      LogicalKeyboardKey.keyB when hw.isControlPressed && !hw.isAltPressed => _run(_toggleRail),
      LogicalKeyboardKey.keyD when hw.isControlPressed && _inPr && !_typing() => _run(() => _pr!.moveCursor(10)),
      LogicalKeyboardKey.keyU when hw.isControlPressed && _inPr && !_typing() => _run(() => _pr!.moveCursor(-10)),
      LogicalKeyboardKey.tab when _inPicker && !hw.isControlPressed && !hw.isAltPressed => _run(_prTab),
      final k when _isArrow(k) && hw.isControlPressed && !hw.isAltPressed && !hw.isMetaPressed &&
          (!_typing() || k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) =>
        _run(() => _ctrlArrow(k)),
      LogicalKeyboardKey.tab when _railFocus.hasFocus && !hw.isControlPressed && !hw.isAltPressed =>
        _run(() => _tabFromRail(hw.isShiftPressed ? -1 : 1)),
      LogicalKeyboardKey.tab when _hasNoTab && !_typing() && !hw.isControlPressed && !hw.isAltPressed =>
        _run(_focusRail),
      _ when hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed || _typing() => false,
      _ when e.character == '?' => _run(() => _setMode(Mode.help)),
      // Shift+C: also in Help (a capital C is not search text there); Help's own search field is typing.
      _ when e.character == 'C' => _run(_openBranchSwitcher),
      _ when e.character == '/' && _mode == Mode.help => _run(() => _helpKey.currentState?.startSearch()),
      _ when _mode == Mode.help && _printable(e.character) => _run(() => _helpKey.currentState?.type(e.character!)),
      // `b` (bug): the debug bar, as the bug button in the status bar; in Help it is search text.
      LogicalKeyboardKey.keyB when !hw.isShiftPressed => _run(() => debugBarVisible.value = !debugBarVisible.value),
      _ when _railFocus.hasFocus => false,
      _ when _mode == Mode.pullRequest => _prKey(e),
      _ => false,
    };
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _altKey(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.bracketRight) return _run(() => _stepMode(1));
    if (k == LogicalKeyboardKey.bracketLeft) return _run(() => _stepMode(-1));
    final i = _digits.indexOf(k);
    return i >= 0 && _run(() => _setMode(Mode.values[i]));
  }

  bool get _inPr => _mode == Mode.pullRequest && _pr != null;

  /// A revision picker has the keyboard: Tab still moves on, as it does from the panes.
  bool get _inPicker => _inPr && (_pr!.baseFocus.hasFocus || _pr!.headFocus.hasFocus);

  /// Tab / Shift+Tab in Pull request: base picker, head picker, files, commits, diff.
  void _prTab() {
    final pr = _pr;
    if (pr == null) return;
    final delta = HardwareKeyboard.instance.isShiftPressed ? -1 : 1;
    if (pr.leavesCycle(delta)) return _focusRail();
    (pr.nextPane(delta) ?? _focus).requestFocus();
  }

  void _prNavigate(NavKey k) {
    switch (k.dir) {
      case NavDir.up || NavDir.down:
        _prMove(k.delta, big: k.big);
      case NavDir.left:
        _prLeft();
      case NavDir.right:
        _pr?.movePane(1);
    }
  }

  /// Left in Pull request: from the diff back to its list; from a list to the rail.
  void _prLeft() {
    final pr = _pr;
    if (pr == null) return;
    pr.pane == PrPane.diff ? pr.movePane(-1) : _focusRail();
  }

  // The mode rail ----------------------------------------------------------------------------------

  void _focusRail() {
    setState(() => _railCursor = _mode.index + 1);
    _railFocus.requestFocus();
  }

  void _railMove(int dir) => setState(() => _railCursor = (_railCursor + dir).clamp(0, Mode.values.length));

  /// Keys while the rail has the keyboard: Up / Down (k, j, w, s) move the cursor over the
  /// expand / collapse button and the modes; Enter, Right (l, d) or Space presses the button, or
  /// picks the mode under the cursor and goes into it; Esc goes back.
  KeyEventResult _railKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) return KeyEventResult.ignored;
    final key = e.logicalKey, nav = navKey(e);
    if (nav != null && nav.vertical) {
      _railMove(nav.delta);
    } else if (nav?.dir == NavDir.right || key == LogicalKeyboardKey.enter || e.character == ' ') {
      _railCursor == 0 ? _toggleRail() : _setMode(Mode.values[_railCursor - 1]);
    } else if (key == LogicalKeyboardKey.escape) {
      _focusMode(_mode);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Tab / Shift+Tab from the rail: into the first (last) stop of the shown mode.
  void _tabFromRail(int delta) {
    final forward = delta > 0;
    switch (_mode) {
      case Mode.pullRequest when _pr != null:
        if (forward) {
          _pr!.baseFocus.requestFocus();
        } else {
          _pr!.goLastPane();
          _focus.requestFocus();
        }
      case Mode.changes:
        _changesKey.currentState?.enterFromRail(forward: forward);
      case Mode.tasks:
        _tasksKey.currentState?.enterFromRail(forward: forward);
      case Mode.directories:
        _dirsKey.currentState?.enterFromRail(forward: forward);
      default:
        _focusMode(_mode);
    }
  }

  /// Ctrl+arrow: the pane in that direction. Up / Down also work in text fields (a picker, the
  /// commit message); Left / Right do not, they move the text cursor there.
  void _ctrlArrow(LogicalKeyboardKey k) {
    final vertical = k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown;
    final dir = k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowLeft ? -1 : 1;
    if (_railFocus.hasFocus) {
      if (vertical) {
        _railMove(dir);
      } else if (dir > 0) {
        _focusMode(_mode);
      }
      return;
    }
    switch (_mode) {
      case Mode.pullRequest when _pr != null:
        if (vertical) {
          _pr!.vertical(dir, _focus).requestFocus();
        } else if (dir < 0) {
          _prLeft();
        } else {
          _pr!.movePane(1);
          _focus.requestFocus();
        }
      case Mode.changes:
        _changesKey.currentState?.ctrlArrow(vertical: vertical, dir: dir);
      case Mode.tasks:
        _tasksKey.currentState?.ctrlArrow(vertical: vertical, dir: dir);
      default:
        if (!vertical && dir < 0) _focusRail();
    }
  }

  static bool _isArrow(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.arrowDown ||
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight;

  /// Modes with no Tab of their own (Help, the connect screen): Tab goes to the rail and back.
  bool get _hasNoTab => _mode == Mode.help || SessionScope.read(context).conn != Conn.connected;

  /// Pull request keys that aren't characters: Enter, Esc, Tab, arrows; the rest go to [_prKeys].
  bool _prKey(KeyEvent e) {
    final pr = _pr;
    if (pr == null) return false;
    final action = switch (e.logicalKey) {
      LogicalKeyboardKey.escape when pr.narrowed != null => pr.showAllCommits,
      LogicalKeyboardKey.enter => pr.enter,
      LogicalKeyboardKey.tab => _prTab,
      _ => null,
    };
    if (action != null) return _run(action);
    // The arrows, hjkl and wasd are one set of keys (see nav_keys.dart); a pending `g` or `z`
    // owns the next key (gs, zw).
    final nav = _prKeys.pending ? null : navKey(e);
    if (nav != null) return _run(() => _prNavigate(nav));
    return _prKeys.press(e.character);
  }

  /// Up / Down: move in the active pane; past the top of FILES CHANGED the head picker gets the keyboard.
  void _prMove(int delta, {bool big = false}) => _pr?.moveCursor(delta, big: big)?.requestFocus();

  /// o: the selected file in Neovim at the current hunk.
  Future<void> _openPr() async {
    final err = await _pr?.openCurrent();
    if (mounted) showActionError(context, err);
  }

  /// A key that types a character (not Enter, Esc or the arrows).
  static bool _printable(String? c) => c != null && c.length == 1 && c.codeUnitAt(0) >= 32;

  static bool _run(void Function() f) {
    f();
    return true;
  }

  /// For the debug bar: what the active pane of the shown mode is, in the interface's words.
  String _paneRole() => switch (_mode) {
    Mode.pullRequest when _pr != null => prPaneRoles[_pr!.pane.name] ?? _mode.label,
    Mode.changes => changesPaneRoles[_changesKey.currentState?.paneName] ?? _mode.label,
    Mode.tasks => tasksPaneRoles[_tasksKey.currentState?.pane.name] ?? _mode.label,
    _ => _mode.label,
  };

  /// For the debug bar: the mode and where its keys act.
  List<String> _debugInfo() => switch (_mode) {
    Mode.pullRequest => ['Mode: ${_mode.label}', ...?_prDebug()],
    Mode.changes => ['Mode: ${_mode.label}', ...?_changesKey.currentState?.debugInfo],
    _ => ['Mode: ${_mode.label}'],
  };

  /// The Pull request items: the commit under the cursor (the active one in COMMITS), file, hunk.
  List<String>? _prDebug() {
    final pr = _pr;
    if (pr == null) return null;
    final at = pr.commits.isEmpty ? null : pr.commits[pr.commitCursor.clamp(0, pr.commits.length - 1)];
    return [
      'Commit: ${at == null ? '-' : '${pr.commitCursor + 1} of ${pr.commits.length} ${at.short}'}',
      'File: ${pr.selected ?? '-'}',
      'Hunk: ${pr.hunk < 0 ? '-' : pr.hunk + 1}',
    ];
  }

  // Layout -------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    if (s.conn == Conn.connected) {
      _pr ??= PrState(s);
      _ws ??= Workspace(s);
    }
    _dirs ??= DirsState(s);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: _railAndModes(s.conn == Conn.connected),
        // The bars are the Scaffold's bottom bar, so a message slides in above them, not over them.
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: debugBarVisible,
              builder: (context, on, _) => on ? DebugBar(pane: _paneRole, info: _debugInfo) : const SizedBox.shrink(),
            ),
            const StatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _railAndModes(bool connected) => Row(
    children: [
      Focus(
        focusNode: _railFocus,
        onKeyEvent: _railKey,
        child: ListenableBuilder(
          listenable: Listenable.merge([SessionScope.read(context).diffPrefs, _railFocus]),
          builder: (context, _) => ModeRail(
            mode: _mode,
            expanded: _expanded,
            layout: _pr == null ? null : SessionScope.read(context).diffPrefs.layout,
            cursor: _railFocus.hasFocus && _railCursor > 0 ? Mode.values[_railCursor - 1] : null,
            toggleCursor: _railFocus.hasFocus && _railCursor == 0,
            onSelect: _setMode,
            onStep: _stepMode,
            onToggle: _toggleRail,
            onLayout: _setLayout,
          ),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: _content(connected)),
    ],
  );

  Widget _help() => HelpView(key: _helpKey, onLeave: _focus.requestFocus);

  /// Help works without Neovim; the other modes need the connection.
  Widget _content(bool connected) {
    if (connected && _pr != null) return _modes();
    return _mode == Mode.help ? _help() : const ConnectScreen();
  }

  Widget _modes() => IndexedStack(
    index: _mode.index,
    children: [
      PrView(state: _pr, reviewing: _reviewing, workspace: _ws, onStopReview: _stopReview, onOpenTask: _openTask),
      ChangesView(key: _changesKey, onRail: _focusRail),
      TasksView(key: _tasksKey, ws: _ws!, onReview: _review, onRail: _focusRail),
      DirsView(key: _dirsKey, state: _dirs!, onRail: _focusRail, onOpenTasks: () => _setMode(Mode.tasks)),
      _help(),
    ],
  );
}
