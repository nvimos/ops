import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/services.dart';

import '../state/add_ignore.dart';
import '../state/log_state.dart';
import '../state/settings.dart';
import '../state/repos.dart';
import '../state/pr.dart';
import '../state/session.dart';
import '../tasks/model.dart';
import '../tasks/workspace.dart';
import '../timing/ui_timing.dart';
import 'add_ignore_view.dart';
import 'changes_view.dart';
import 'connect.dart';
import 'dirs_view.dart';
import 'error_view.dart';
import 'key_sequence.dart';
import 'log_view.dart';
import 'settings_view.dart';
import 'nav_keys.dart';
import 'help_view.dart';
import 'debug_bar.dart';
import 'mode_placeholder.dart';
import 'notice_bar.dart';
import 'nav_history.dart';
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
  ReposState? _dirs;
  AddIgnoreState? _add;
  LogState? _log;
  SettingsState? _settings;

  /// The session's backend generation the mode states above were made for.
  int _epoch = 0;
  final _focus = FocusNode(debugLabel: 'shell');

  /// The task whose branch the Pull request view is reviewing (its Verify list shows beside it).
  Task? _reviewing;

  /// Where the mouse's back button goes: the places jumps came from, newest last.
  final _history = NavHistory();

  /// The rail's arrangement (order and hidden modes), from the local state file.
  RailState? _rail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rail == null) {
      final rail = RailState(SessionScope.read(context).prefs)..addListener(_onRailChanged);
      _rail = rail;
      // A saved state may hide the mode the app starts on (Pull request): show the nearest one.
      if (!rail.visible.contains(_mode) && rail.visible.isNotEmpty) _mode = _nearestVisible(_mode, rail.visible);
    }
  }

  /// The visible mode closest to [mode] in the full order, so hiding the shown mode does not jump
  /// the user to the top of the rail.
  Mode _nearestVisible(Mode mode, List<Mode> shown) {
    final all = _rail?.order ?? Mode.values;
    final at = all.indexOf(mode);
    for (var i = at - 1; i >= 0; i--) {
      if (shown.contains(all[i])) return all[i];
    }
    for (var i = at + 1; i < all.length; i++) {
      if (shown.contains(all[i])) return all[i];
    }
    return shown.first;
  }

  /// The rail's arrangement changed (a drag, or a hide/show): show the rail again, and leave the
  /// mode it holds if that one was just hidden.
  void _onRailChanged() {
    if (!mounted) return;
    final shown = _shownModes;
    if (!shown.contains(_mode)) {
      if (shown.isNotEmpty) _setMode(_nearestVisible(_mode, shown), record: false);
    } else {
      setState(() {});
    }
  }

  List<Mode> get _shownModes => _rail?.visible ?? Mode.values;

  /// A directory was named on the command line: its opening mode was shown once.
  bool _openedProject = false;
  final _tasksKey = GlobalKey<TasksViewState>();
  final _changesKey = GlobalKey<ChangesViewState>();
  final _dirsKey = GlobalKey<DirsViewState>();
  final _addKey = GlobalKey<AddIgnoreViewState>();
  final _settingsKey = GlobalKey<SettingsViewState>();
  final _helpKey = GlobalKey<HelpViewState>();

  /// The mode rail takes the keyboard (Left from the leftmost pane, Tab round the cycle); its cursor
  /// starts on the current mode.
  final _railFocus = FocusNode(debugLabel: 'rail');

  /// The rail cursor: 0 is the expand / collapse button, 1.. are the modes in rail order.
  int _railCursor = 1;

  /// The keys the rail takes for itself: `gi` goes to the first input of the mode shown.
  late final _railKeys = KeySequence({'gi': _focusFirstInput});
  late final _prKeys = KeySequence({
    'v': () => _pr?.toggleLayout(),
    'Z': () => _pr?.cycleLayout(), // the next view: unified, side by side, merge
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
    _rail?.dispose();
    _pr?.dispose();
    _ws?.dispose();
    _dirs?.dispose();
    _add?.dispose();
    _log?.dispose();
    _settings?.dispose();
    super.dispose();
  }

  // Event handlers -------------------------------------------------------------------------------

  void _openTask(String id) {
    // From another mode (the review panel's banner) the mode switch records the way back; from one
    // task to another (a link in the detail) Tasks records the task it leaves.
    final inTasks = _mode == Mode.tasks;
    _setMode(Mode.tasks);
    _tasksKey.currentState?.openTask(id, record: inTasks);
  }

  void _review(Task t, String branch) {
    final previous = _mode;
    _history.push(
      NavPlace('Back to ${previous.label}', () {
        if (_reviewing != null) _stopReview();
        _setMode(previous, record: false);
      }),
    );
    setState(() => _reviewing = t);
    _setMode(Mode.pullRequest, record: false);
    _pr!.pick(base: _ws!.defaultBranch, head: branch);
  }

  /// Open the Active Directory in the first mode with something to do: Pull request when there is
  /// a branch to review, else Changes when the checkout is dirty, else Tasks.
  Future<void> _openProject() async {
    final target = await _dirs!.openingTarget();
    if (!mounted) return;
    _setMode(switch (target) {
      OpenTarget.pullRequest => Mode.pullRequest,
      OpenTarget.changes => Mode.changes,
      OpenTarget.tasks => Mode.tasks,
    });
  }

  void _stopReview() => setState(() => _reviewing = null);

  void _toggleRail() => setState(() => _expanded = !_expanded);

  /// The rail's right-click menu: hide a mode; the listener shows another if it was the current one.
  void _hideMode(Mode mode) => _rail?.hide(mode);

  /// Switch modes and give the keyboard to the new one (Tasks and Directories have their own keys).
  /// Shows [m]; [record] puts the mode being left on the back stack (a composite jump records the
  /// whole place itself, once). The keyboard goes to the mode's own pane, or with [onRail] to its
  /// item in the mode rail, so the keys that follow start from the mode that is shown.
  void _setMode(Mode m, {bool onRail = false, bool record = true}) {
    if (record && m != _mode) {
      final previous = _mode;
      _history.push(NavPlace('Back to ${previous.label}', () => _setMode(previous, record: false)));
    }
    final click = _railClick;
    _railClick = null;
    click?.mark('tap'); // mouse down -> onTap: a gesture that waits (a double tap) shows here
    click?.markPainted();
    UiTiming.instance.span('shell.setMode').markPainted(); // setState -> the new mode on screen
    setState(() => _mode = m);
    WidgetsBinding.instance.addPostFrameCallback((_) => onRail ? _focusRail() : _focusMode(m));
  }

  /// Started when a mouse button goes down on the rail; [_setMode] marks the tap and the paint.
  Span? _railClick;

  void _onRailPointerDown(PointerDownEvent _) => _railClick = UiTiming.instance.span('shell.railClick');

  /// The mouse's back button: show the previous place (a task link, a review, a mode switch).
  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons & kBackMouseButton != 0) _history.back();
  }

  void _openSettings() {
    _settings?.ensureDetected();
    _settingsKey.currentState?.focus.requestFocus();
  }

  void _focusMode(Mode m) => switch (m) {
    Mode.changes => _changesKey.currentState?.focus.requestFocus(),
    Mode.tasks => _tasksKey.currentState?.focus.requestFocus(),
    Mode.repos => _dirsKey.currentState?.focusFilter(),
    Mode.addIgnore => _addKey.currentState?.focus.requestFocus(),
    Mode.settings => _openSettings(),
    _ => _focus.requestFocus(),
  };

  /// Shift+C: the Changes mode, with the branch switcher focused and its list open.
  void _openBranchSwitcher() {
    _setMode(Mode.changes);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changesKey.currentState?.openBranchSwitcher());
  }

  /// Shift+P: the Pull request mode, with the head picker focused and its list open.
  void _openHeadPicker() {
    _setMode(Mode.pullRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pr?.openHead.value++);
  }

  /// The next or previous shown mode, wrapping round; hidden modes are skipped. A step is not a
  /// place to go back to: four steps would take four presses of the back button.
  void _stepMode(int delta, {bool onRail = false}) {
    final shown = _shownModes;
    if (shown.isEmpty) return;
    final at = shown.indexOf(_mode);
    _setMode(shown[at < 0 ? 0 : (at + delta) % shown.length], onRail: onRail, record: false);
  }

  // Keys -----------------------------------------------------------------------------------------

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
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
      _ when _railFocus.hasFocus && _railKeys.press(e.character) => true,
      _ when e.character == '?' => _run(() => _setMode(Mode.help)),
      // Shift+C: also in Help (a capital C is not search text there); Help's own search field is typing.
      _ when e.character == 'C' => _run(_openBranchSwitcher),
      _ when e.character == 'P' => _run(_openHeadPicker),
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
    if (k == LogicalKeyboardKey.bracketRight) return _run(() => _stepMode(1, onRail: true));
    if (k == LogicalKeyboardKey.bracketLeft) return _run(() => _stepMode(-1, onRail: true));
    final i = _digits.indexOf(k), shown = _shownModes;
    // Alt+1..9 follow the rail, not the enum: a hidden mode is skipped with the rest.
    return i >= 0 && i < shown.length && _run(() => _setMode(shown[i], onRail: true));
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

  /// `gi` with the rail focused: the first input field of the mode shown (Changes: the branch switcher).
  void _focusFirstInput() {
    switch (_mode) {
      case Mode.pullRequest:
        _pr?.baseFocus.requestFocus();
      case Mode.changes:
        _changesKey.currentState?.focusBranch();
      case Mode.tasks:
        _tasksKey.currentState?.filterFocus.requestFocus();
      case Mode.repos:
        _dirsKey.currentState?.focusFilter();
      case Mode.addIgnore:
        _addKey.currentState?.focusFilter();
      case Mode.help:
        _helpKey.currentState?.focusSearch();
      case Mode.history || Mode.settings || Mode.log:
        break;
    }
  }

  void _focusRail() {
    setState(() => _railCursor = _shownModes.indexOf(_mode) + 1);
    _railFocus.requestFocus();
  }

  void _railMove(int dir) => setState(() => _railCursor = (_railCursor + dir).clamp(0, _shownModes.length));

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
      final shown = _shownModes;
      if (_railCursor == 0 || shown.isEmpty) {
        _toggleRail();
      } else {
        _setMode(shown[(_railCursor - 1).clamp(0, shown.length - 1)]);
      }
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
      case Mode.repos:
        _dirsKey.currentState?.enterFromRail(forward: forward);
      case Mode.addIgnore:
        _addKey.currentState?.enterFromRail(forward: forward);
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

  /// A different backend (or none) than the one the mode states were made for: they hold its rows,
  /// branches and tasks, so they are dropped and made again for the new one.
  void _resetForNewBackend(Session s) {
    if (s.epoch == _epoch) return;
    _epoch = s.epoch;
    // disposed after this frame: the views of the old states are still in the tree until it ends
    final old = <ChangeNotifier?>[_pr, _ws, _dirs, _add, _log, _settings];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final o in old) {
        o?.dispose();
      }
    });
    _pr = _ws = _dirs = _add = _log = _settings = null;
    _openedProject = false;
  }

  // Layout -------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    _resetForNewBackend(s);
    if (s.conn == Conn.connected) {
      _pr ??= PrState(s);
      _ws ??= Workspace(s);
      _dirs ??= ReposState(s);
      _add ??= AddIgnoreState(s);
      _log ??= LogState(s);
      _settings ??= SettingsState(s, onDepth: (d) => _dirs?.browser.useDepth(d));
      _dirs!.onScan = _log!.addScan;
      if (s.openProjectOnConnect && !_openedProject) {
        _openedProject = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && SessionScope.read(context).conn == Conn.connected) _openProject();
        });
      }
    } else {
      _dirs ??= ReposState(s);
    }
    return NavScope(
      history: _history,
      child: Listener(
        // The mouse's back button works over any pane, like a browser's.
        onPointerDown: _onPointerDown,
        child: Focus(
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
                  builder: (context, on, _) =>
                      on ? DebugBar(pane: _paneRole, info: _debugInfo) : const SizedBox.shrink(),
                ),
                NoticeBar(notices: SessionScope.read(context).notices),
                const StatusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _railAndModes(bool connected) {
    final shown = _shownModes;
    return Row(
      children: [
        Focus(
          focusNode: _railFocus,
          onKeyEvent: _railKey,
          child: ListenableBuilder(
            listenable: Listenable.merge([SessionScope.read(context).diffPrefs, SessionScope.read(context).conflicts, _railFocus]),
            builder: (context, _) => Listener(
              onPointerDown: _onRailPointerDown,
              child: ModeRail(
                mode: _mode,
                modes: shown,
                expanded: _expanded,
                cursor: _railFocus.hasFocus && _railCursor > 0 && shown.isNotEmpty
                    ? shown[(_railCursor - 1).clamp(0, shown.length - 1)]
                    : null,
                toggleCursor: _railFocus.hasFocus && _railCursor == 0,
                onSelect: _setMode,
                onStep: _stepMode,
                onToggle: _toggleRail,
                onReorder: _rail?.reorderVisible,
                onHide: _hideMode,
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _content(connected)),
      ],
    );
  }

  Widget _help() => HelpView(key: _helpKey, onLeave: _focus.requestFocus);

  /// Help works without Neovim; the other modes need the connection.
  Widget _content(bool connected) {
    if (connected && _pr != null) return _modes();
    return _mode == Mode.help ? _help() : const ConnectScreen();
  }

  /// Every mode stays built (its state and scroll survive a switch), but only the shown one is in the
  /// semantics tree. Without the ExcludeSemantics the hidden modes kept sending semantics updates for
  /// nodes the Windows accessibility tree never got ("Failed to update ui::AXTree, error: N will not be
  /// in the tree and is not the new root", in bursts while a hidden mode refreshed).
  Widget _modes() => IndexedStack(
    index: _mode.index,
    children: [
      for (final (i, child) in _modeViews().indexed) ExcludeSemantics(excluding: i != _mode.index, child: child),
    ],
  );

  /// The mode views, kept as the same widget instances while their inputs stay the same. A mode
  /// switch is a setState of the shell; with new instances every view, hidden ones too, rebuilt its
  /// whole subtree on each click (a few hundred ms in a debug build: the rail answered late, as if
  /// it waited for a double click). An identical widget is skipped by Flutter, so a switch now only
  /// rebuilds the IndexedStack and the two ExcludeSemantics that change. The views still rebuild on
  /// their own listeners and inherited widgets.
  List<Widget> _modeViews() {
    final inputs = (_pr, _reviewing, _ws, _add, _dirs, _settings, _log);
    if (_views != null && _viewsInputs == inputs) return _views!;
    _viewsInputs = inputs;
    return _views = [
      PrView(state: _pr, reviewing: _reviewing, workspace: _ws, onStopReview: _stopReview, onOpenTask: _openTask),
      ChangesView(key: _changesKey, onRail: _focusRail),
      AddIgnoreView(key: _addKey, state: _add!, onRail: _focusRail),
      const ModePlaceholder(Mode.history),
      TasksView(key: _tasksKey, ws: _ws!, onReview: _review, onRail: _focusRail),
      DirsView(key: _dirsKey, state: _dirs!, onRail: _focusRail, onOpen: _openProject),
      SettingsView(key: _settingsKey, state: _settings!, layout: _rail, onRail: _focusRail),
      LogView(log: _log!),
      _help(),
    ];
  }

  List<Widget>? _views;
  Object? _viewsInputs;
}
