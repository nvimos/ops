import 'dart:async' show Timer, scheduleMicrotask;
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../rpc/stats.dart';
import 'theme.dart';

/// Whether the debug bar is shown; the status bar's bug button toggles it.
final debugBarVisible = ValueNotifier<bool>(false);

/// What each labelled focus node is, in the interface's own words. The `debugLabel`s are set where
/// the nodes are made. Nodes in [paneNodes] stand for several panes (their key handler serves the
/// whole mode), so the mode says which pane it is.
const focusRoles = {
  'base picker': 'Base revision field',
  'head picker': 'Head revision field',
  'commit message': 'Commit message field',
  'branch switcher': 'Branch switcher field',
  'dirs filter': 'Directory filter field',
  'tasks filter': 'Task filter field',
  'dirs': 'Directory list',
  'tasks': 'Task list',
  'task detail text': 'Task detail text',
  'changes': 'Changes',
  'shell': 'App',
  'rail': 'Mode rail',
};

/// The labels in [focusRoles] whose pane is decided by the mode.
const paneNodes = {'shell', 'changes', 'tasks'};

/// Panes by what they are in the interface: Pull request and Changes, by the state's pane name.
const prPaneRoles = {'files': 'Files changed list', 'commits': 'Commits list', 'diff': 'Diff'};
const tasksPaneRoles = {'nav': 'Facets', 'list': 'Task list', 'detail': 'Task detail'};
const changesPaneRoles = {'staged': 'Staged files list', 'unstaged': 'Changed files list', 'diff': 'Diff'};

/// Widget classes that are an interface element on their own, for focus without a labelled node
/// around it (dialogs, the command palette). Matched by class name.
const widgetRoles = {'EditableText': 'Text field'};

/// What the focused [node] is for the user: the nearest labelled node's role from [focusRoles], or
/// [pane] (what the mode says is active) for a [paneNodes] node, else a [widgetRoles] element.
String uiRole(FocusNode? node, {required String pane}) {
  if (node == null) return 'nothing';
  for (final n in [node, ...node.ancestors]) {
    final label = n.debugLabel;
    if (label == null || !focusRoles.containsKey(label)) continue;
    return paneNodes.contains(label) ? pane : focusRoles[label]!;
  }
  final w = node.context?.widget;
  final inField = w is EditableText || node.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  return inField ? widgetRoles['EditableText']! : 'unlabelled element';
}

/// What has the keyboard, for finding out where the focus goes: the interface element that is
/// focused (by its role, not its class), the mode's own state, and the last key pressed, one item
/// per line, three lines high. It updates on every focus change and key press.
class DebugBar extends StatefulWidget {
  const DebugBar({super.key, required this.pane, required this.info});

  /// The active pane of the shown mode, by its role ("Commits list"), or the mode's name.
  final ValueGetter<String> pane;

  /// The current mode's own state, one item per line (mode, file, commit, hunk).
  final ValueGetter<List<String>> info;

  @override
  State<DebugBar> createState() => _DebugBarState();
}

class _DebugBarState extends State<DebugBar> {
  String _key = '-';
  String _mouse = '-';
  int _downButtons = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_refresh);
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_refresh);
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Sees every key before the app does; the state it shows is read after the key was handled.
  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      _key = keyName(e);
      Future<void>.delayed(Duration.zero, _refresh);
    }
    return false;
  }

  /// Sees every pointer event: a button going down or up, and the wheel (not the moves).
  void _onPointer(PointerEvent e) {
    final name = switch (e) {
      PointerDownEvent() => '${buttonName(_downButtons = e.buttons)} down',
      PointerUpEvent() => '${buttonName(_downButtons)} up',
      PointerScrollEvent() when e.scrollDelta.dy != 0 || e.scrollDelta.dx != 0 =>
        'Wheel ${(e.scrollDelta.dy != 0 ? e.scrollDelta.dy : e.scrollDelta.dx) > 0 ? 'down' : 'up'}',
      _ => null,
    };
    if (name == null) return;
    _mouse = [..._modifiers(), name].join('+');
    scheduleMicrotask(_refresh);
    // A click or wheel step changes the focus and the mode's state after this event; read them again
    // once the frame that shows the change is done.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.endOfFrame.then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final role = uiRole(FocusManager.instance.primaryFocus, pane: widget.pane());
    final items = ['Focus: $role', ...widget.info(), 'Key: $_key', 'Mouse: $_mouse'];
    // Columns of three items each: the next column starts after the third line, whatever the
    // font's exact line height (a Wrap in a box of three lines broke too early).
    final columns = [for (var i = 0; i < items.length; i += _lines) items.sublist(i, math.min(i + _lines, items.length))];
    return Container(
      height: _lines * 11 * 1.3 + 10 + 2 + 12,
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        color: C.surface2,
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _DebugBox(child: _columns(columns))),
          const SizedBox(width: 6),
          const _DebugBox(child: NetworkMonitor()),
        ],
      ),
    );
  }

  /// The columns side by side; what does not fit next to the network monitor is cut off.
  Widget _columns(List<List<String>> columns) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final column in columns)
          Padding(
            padding: const EdgeInsets.only(right: 28),
            child: debugTable(column),
          ),
      ],
    ),
  );
}

const _debugStyle = TextStyle(fontSize: 11, height: 1.3, fontFamily: mono, color: C.yellow);

/// Three lines high; more items continue in the next column.
const _lines = 3;

/// One widget of the debug bar: its own bordered box, so neighbours read as separate things.
class _DebugBox extends StatelessWidget {
  const _DebugBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    alignment: Alignment.topLeft,
    decoration: BoxDecoration(
      color: C.bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: C.border),
    ),
    child: child,
  );
}

/// "Label: value" items as a table of two columns, the labels right-aligned so the colons line up.
/// An item ending in `!` is shown in red (the `!` is not shown).
Widget debugTable(List<String> items) => Table(
  defaultColumnWidth: const IntrinsicColumnWidth(),
  children: [for (final item in items) _row(item)],
);

TableRow _row(String item) {
  final warn = item.endsWith('!');
  final text = warn ? item.substring(0, item.length - 1) : item;
  final style = warn ? _debugStyle.copyWith(color: C.red) : _debugStyle;
  final colon = text.indexOf(': ');
  final (label, value) = colon < 0 ? ('', text) : (text.substring(0, colon + 1), text.substring(colon + 2));
  return TableRow(
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(label, maxLines: 1, style: style),
        ),
      ),
      Text(value, maxLines: 1, style: style),
    ],
  );
}

/// The health of the conversation with Neovim: requests sent and per second, how many wait for an
/// answer (the queue), how long answers take. Red when requests pile up or one waits long.
class NetworkMonitor extends StatefulWidget {
  const NetworkMonitor({super.key, this.stats});

  final RpcStats? stats;

  /// More requests than this waiting at once, or one waiting longer than [slowWait], is a problem.
  static const queueWarn = 5;
  static const slowWait = Duration(milliseconds: 500);

  @override
  State<NetworkMonitor> createState() => _NetworkMonitorState();
}

class _NetworkMonitorState extends State<NetworkMonitor> {
  Timer? _timer;
  RpcStats get _stats => widget.stats ?? RpcStats.instance;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => debugTable(networkLines(_stats));
}

/// The monitor's three lines.
List<String> networkLines(RpcStats s) {
  final queued = s.inFlight;
  final stuck = queued > NetworkMonitor.queueWarn || s.oldestWait > NetworkMonitor.slowWait;
  return [
    'Requests: ${s.total} sent, ${s.perSecond.toStringAsFixed(1)}/s${s.failed > 0 ? ', ${s.failed} failed' : ''}',
    'Waiting: $queued now, peak ${s.peakInFlight}${queued > 0 ? ', oldest ${_ms(s.oldestWait)}' : ''}${stuck ? '!' : ''}',
    'Answers: p50 ${_ms(s.percentile(50))}, p95 ${_ms(s.percentile(95))}, max ${_ms(s.slowest)}',
  ];
}

String _ms(Duration d) => d.inMilliseconds >= 1000 ? '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s' : '${d.inMilliseconds} ms';

/// The key as typed: modifiers, then the character or the key's name ("Ctrl+Alt+j", "ArrowRight").
String keyName(KeyEvent e) {
  final c = e.character;
  final name = c != null && c.trim().isNotEmpty ? c : e.logicalKey.keyLabel.isEmpty ? e.logicalKey.debugName ?? '?' : e.logicalKey.keyLabel;
  return [..._modifiers(shift: c == null || c.trim().isEmpty), name].join('+');
}

List<String> _modifiers({bool shift = true}) {
  final hw = HardwareKeyboard.instance;
  return [if (hw.isControlPressed) 'Ctrl', if (hw.isAltPressed) 'Alt', if (hw.isShiftPressed && shift) 'Shift'];
}

/// The mouse button in a pointer event's `buttons` bit field: Left, Right, Middle (or the others).
String buttonName(int buttons) {
  final names = [
    if (buttons & kPrimaryButton != 0) 'Left',
    if (buttons & kSecondaryButton != 0) 'Right',
    if (buttons & kMiddleMouseButton != 0) 'Middle',
    if (buttons & kBackMouseButton != 0) 'Back',
    if (buttons & kForwardMouseButton != 0) 'Forward',
  ];
  return names.isEmpty ? 'Button' : names.join('+');
}
