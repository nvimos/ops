import 'dart:async' show scheduleMicrotask;
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

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
  'dirs filter': 'Directory filter field',
  'tasks filter': 'Task filter field',
  'dirs': 'Directory list',
  'tasks': 'Task list',
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

  static const _style = TextStyle(fontSize: 11, height: 1.3, fontFamily: mono, color: C.yellow);

  /// Three lines high; more items continue in the next column.
  static const _lines = 3;

  /// "Label: value" as two cells, the label right-aligned, so the colons of a column line up.
  TableRow _row(String item) {
    final colon = item.indexOf(': ');
    final (label, value) = colon < 0 ? ('', item) : (item.substring(0, colon + 1), item.substring(colon + 2));
    return TableRow(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(label, maxLines: 1, style: _style),
          ),
        ),
        Text(value, maxLines: 1, style: _style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = uiRole(FocusManager.instance.primaryFocus, pane: widget.pane());
    final items = ['Focus: $role', ...widget.info(), 'Key: $_key', 'Mouse: $_mouse'];
    // Columns of three items each: the next column starts after the third line, whatever the
    // font's exact line height (a Wrap in a box of three lines broke too early).
    final columns = [for (var i = 0; i < items.length; i += _lines) items.sublist(i, math.min(i + _lines, items.length))];
    return Container(
      height: _lines * 11 * 1.3 + 14,
      width: double.infinity,
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const BoxDecoration(
        color: C.surface2,
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final column in columns)
            Padding(
              padding: const EdgeInsets.only(right: 28),
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [for (final item in column) _row(item)],
              ),
            ),
        ],
      ),
    );
  }
}

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
