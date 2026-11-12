import 'package:flutter/services.dart';

enum NavDir { up, down, left, right }

/// A direction key: one of the arrow keys, `h j k l` or `w a s d`, which are the same keys. Holding
/// Shift (or typing the capital letter, for up and down) makes it [big]: the long step.
///
/// One exception, for a special layout: the key at D's position on a QWERTY keyboard (found by
/// its scan code) is Right whatever letter the layout puts there. No other key is matched by position.
class NavKey {
  const NavKey(this.dir, {this.big = false});

  final NavDir dir;
  final bool big;

  bool get vertical => dir == NavDir.up || dir == NavDir.down;

  /// -1 for up and left, 1 for down and right.
  int get delta => dir == NavDir.up || dir == NavDir.left ? -1 : 1;
}

/// The direction [e] stands for, or null for any other key. Every mode reads its direction keys
/// through this, so the arrows, hjkl and WASD cannot drift apart. Keys with Ctrl, Alt or Meta are
/// not direction keys (Ctrl+arrow jumps between panes elsewhere).
///
/// The capital horizontal letters are not direction keys: Shift+A is a command in Tasks.
NavKey? navKey(KeyEvent e) {
  final hw = HardwareKeyboard.instance;
  if (hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) return null;
  final shift = hw.isShiftPressed;
  final byKey = switch (e.logicalKey) {
    LogicalKeyboardKey.arrowUp => NavKey(NavDir.up, big: shift),
    LogicalKeyboardKey.arrowDown => NavKey(NavDir.down, big: shift),
    LogicalKeyboardKey.arrowLeft => const NavKey(NavDir.left),
    LogicalKeyboardKey.arrowRight => const NavKey(NavDir.right),
    _ => null,
  };
  if (byKey != null) return byKey;
  // The one exception: the key where D is on QWERTY, whatever it types (the layout has R there).
  if (e.physicalKey == PhysicalKeyboardKey.keyD) return shift ? null : const NavKey(NavDir.right);
  final c = e.character;
  if (c == null || c.length != 1) return null;
  final capital = c != c.toLowerCase();
  return switch (c.toLowerCase()) {
    'k' || 'w' => NavKey(NavDir.up, big: capital),
    'j' || 's' => NavKey(NavDir.down, big: capital),
    'h' || 'a' when !capital => const NavKey(NavDir.left),
    'l' || 'd' when !capital => const NavKey(NavDir.right),
    _ => null,
  };
}
