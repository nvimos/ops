import 'package:flutter/material.dart';
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
import 'help_view.dart';
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
  late final _prKeys = KeySequence({
    'v': () => _pr?.toggleLayout(),
    'gb': () => _pr?.baseFocus.requestFocus(),
    'gh': () => _pr?.headFocus.requestFocus(),
    'gs': () => _pr?.swap(),
    ']f': () => _pr?.selectNext(1),
    '[f': () => _pr?.selectNext(-1),
    'zw': () => _pr?.toggleWrap(),
    'zR': () => _pr?.expandAllDirs(),
    'zM': () => _pr?.collapseAllDirs(),
    'j': () => _pr?.moveCursor(1),
    'k': () => _pr?.moveCursor(-1),
    'gg': () => _pr?.moveCursor(-_far),
    'G': () => _pr?.moveCursor(_far),
    ']c': () => _pr?.moveHunk(1),
    '[c': () => _pr?.moveHunk(-1),
    'h': () => _pr?.foldSelected(fold: true),
    'l': () => _pr?.foldSelected(fold: false),
    'o': _openPr,
  });

  /// Far enough to reach the first or last item of any list.
  static const _far = 1 << 20;

  @override
  void dispose() {
    _prKeys.dispose();
    _focus.dispose();
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

  void _setLayout(DiffLayout l) => _pr?.setLayout(l);

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

  void _stepMode(int delta) => _setMode(Mode.values[(_mode.index + delta) % Mode.values.length]);

  // Keys -----------------------------------------------------------------------------------------

  static final _noPr = ValueNotifier(0);

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
      _ when hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed || _typing() => false,
      _ when e.character == '?' => _run(() => _setMode(Mode.help)),
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
    final picker = _pr?.nextPane(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
    (picker ?? _focus).requestFocus();
  }

  /// Pull request keys that aren't characters: Enter, Esc, Tab, arrows; the rest go to [_prKeys].
  bool _prKey(KeyEvent e) {
    final pr = _pr;
    if (pr == null) return false;
    final action = switch (e.logicalKey) {
      LogicalKeyboardKey.escape when pr.narrowed != null => pr.showAllCommits,
      LogicalKeyboardKey.enter => pr.enter,
      LogicalKeyboardKey.tab => _prTab,
      LogicalKeyboardKey.arrowDown => () => pr.moveCursor(1),
      LogicalKeyboardKey.arrowUp => () => pr.moveCursor(-1),
      _ => null,
    };
    if (action != null) return _run(action);
    return _prKeys.press(e.character);
  }

  /// o: the selected file in Neovim at the current hunk.
  Future<void> _openPr() async {
    final err = await _pr?.openCurrent();
    if (mounted) showActionError(context, err);
  }

  static bool _run(void Function() f) {
    f();
    return true;
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
        body: Column(
          children: [
            Expanded(child: _railAndModes(s.conn == Conn.connected)),
            const StatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _railAndModes(bool connected) => Row(
    children: [
      ListenableBuilder(
        listenable: _pr ?? _noPr,
        builder: (context, _) => ModeRail(
          mode: _mode,
          expanded: _expanded,
          layout: _pr?.layout,
          onSelect: _setMode,
          onToggle: _toggleRail,
          onLayout: _setLayout,
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: _content(connected)),
    ],
  );

  /// Help works without Neovim; the other modes need the connection.
  Widget _content(bool connected) {
    if (connected && _pr != null) return _modes();
    return _mode == Mode.help ? const HelpView() : const ConnectScreen();
  }

  Widget _modes() => IndexedStack(
    index: _mode.index,
    children: [
      PrView(state: _pr, reviewing: _reviewing, workspace: _ws, onStopReview: _stopReview, onOpenTask: _openTask),
      ChangesView(key: _changesKey),
      TasksView(key: _tasksKey, ws: _ws!, onReview: _review),
      DirsView(key: _dirsKey, state: _dirs!),
      const HelpView(),
    ],
  );
}
