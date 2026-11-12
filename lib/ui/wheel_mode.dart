import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// What the mouse wheel does over a list pane: scroll it (the default), or, after a middle click
/// on the pane, step through its items like Up / Down ([onStep] gets -1 or 1). The next middle click
/// switches back. Shift + the wheel steps whatever the mode.
/// Shift+Insert, with the pointer over the pane, toggles like the middle click (a local-setup exception). While it steps, a thin accent line at the pane's bottom edge says so, and
/// [builder] gets `steps` true so the list can stop scrolling itself.
class WheelMode extends StatefulWidget {
  const WheelMode({super.key, required this.onStep, required this.builder});

  final ValueChanged<int> onStep;
  final Widget Function(BuildContext context, bool steps) builder;

  @override
  State<WheelMode> createState() => WheelModeState();
}

class WheelModeState extends State<WheelMode> {
  bool steps = false;
  bool _hover = false;
  bool _shift = HardwareKeyboard.instance.isShiftPressed;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// While Shift is down the list must not scroll on its own: Windows may send Shift + wheel as a
  /// sideways scroll, which the list would take before the pane could step.
  bool _onKey(KeyEvent e) {
    // EXCEPTION for the user's local setup, not a general rule: their middle mouse button reaches the
    // app as Shift+Insert (a paste key). Over this pane it toggles the wheel mode like a middle click.
    if (_hover &&
        e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.insert &&
        HardwareKeyboard.instance.isShiftPressed) {
      setState(() => steps = !steps);
      return true;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift != _shift) {
      _shift = shift;
      if (mounted) setState(() {});
    }
    return false;
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !(steps || _shift)) return;
    final dy = e.scrollDelta.dy != 0 ? e.scrollDelta.dy : e.scrollDelta.dx;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) => widget.onStep(dy > 0 ? 1 : -1));
  }

  void _down(PointerDownEvent e) {
    if (e.buttons == kMiddleMouseButton) setState(() => steps = !steps);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _hover = true,
    onExit: (_) => _hover = false,
    child: Listener(
      onPointerSignal: _wheel,
      onPointerDown: _down,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: steps ? C.accent : Colors.transparent, width: 2)),
        ),
        child: widget.builder(context, steps || _shift),
      ),
    ),
  );
}
