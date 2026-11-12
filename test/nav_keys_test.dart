import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/nav_keys.dart';

void main() {
  testWidgets('arrows, hjkl and wasd are the same keys; capitals and Shift make the long step', (t) async {
    final seen = <NavKey?>[];
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, e) {
            if (e is KeyDownEvent) seen.add(navKey(e));
            return KeyEventResult.ignored;
          },
          child: const SizedBox(),
        ),
      ),
    );
    Future<NavKey?> press(LogicalKeyboardKey k, {String? ch, bool shift = false, bool ctrl = false}) async {
      if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(k, character: ch);
      if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      return seen.last;
    }

    (NavDir, bool)? of(NavKey? k) => k == null ? null : (k.dir, k.big);

    // Up: k, w, the arrow; Down: j, s; Left: h, a; Right: l, d.
    expect(of(await press(LogicalKeyboardKey.arrowUp)), (NavDir.up, false));
    expect(of(await press(LogicalKeyboardKey.keyK, ch: 'k')), (NavDir.up, false));
    expect(of(await press(LogicalKeyboardKey.keyW, ch: 'w')), (NavDir.up, false));
    expect(of(await press(LogicalKeyboardKey.arrowDown)), (NavDir.down, false));
    expect(of(await press(LogicalKeyboardKey.keyJ, ch: 'j')), (NavDir.down, false));
    expect(of(await press(LogicalKeyboardKey.keyS, ch: 's')), (NavDir.down, false));
    expect(of(await press(LogicalKeyboardKey.arrowLeft)), (NavDir.left, false));
    expect(of(await press(LogicalKeyboardKey.keyH, ch: 'h')), (NavDir.left, false));
    expect(of(await press(LogicalKeyboardKey.keyA, ch: 'a')), (NavDir.left, false));
    expect(of(await press(LogicalKeyboardKey.arrowRight)), (NavDir.right, false));
    expect(of(await press(LogicalKeyboardKey.keyL, ch: 'l')), (NavDir.right, false));
    expect(of(await press(LogicalKeyboardKey.keyD, ch: 'd')), (NavDir.right, false));

    // The long step: Shift+arrow, or the capital letter, for up and down.
    expect(of(await press(LogicalKeyboardKey.arrowDown, shift: true)), (NavDir.down, true));
    expect(of(await press(LogicalKeyboardKey.keyK, ch: 'K', shift: true)), (NavDir.up, true));
    expect(of(await press(LogicalKeyboardKey.keyW, ch: 'W', shift: true)), (NavDir.up, true));
    expect(of(await press(LogicalKeyboardKey.keyS, ch: 'S', shift: true)), (NavDir.down, true));

    // Not direction keys: other letters, the capital horizontal letters (Shift+A is a command in
    // Tasks) and anything with Ctrl.
    expect(await press(LogicalKeyboardKey.keyX, ch: 'x'), isNull);
    expect(await press(LogicalKeyboardKey.keyA, ch: 'A', shift: true), isNull);
    expect(await press(LogicalKeyboardKey.arrowUp, ctrl: true), isNull);
  });

  testWidgets('the key at the D position is Right whatever it types; no other key goes by position', (t) async {
    final seen = <NavKey?>[];
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, e) {
            if (e is KeyDownEvent) seen.add(navKey(e));
            return KeyEventResult.ignored;
          },
          child: const SizedBox(),
        ),
      ),
    );
    Future<NavKey?> press(LogicalKeyboardKey logical, PhysicalKeyboardKey physical, String ch) async {
      await simulateKeyDownEvent(logical, physicalKey: physical, character: ch);
      await simulateKeyUpEvent(logical, physicalKey: physical);
      return seen.last;
    }

    // A layout with R where QWERTY has D: that key types "r" and navigates right.
    expect((await press(LogicalKeyboardKey.keyR, PhysicalKeyboardKey.keyD, 'r'))?.dir, NavDir.right);
    // The same position on QWERTY, and a "d" typed anywhere else, still work.
    expect((await press(LogicalKeyboardKey.keyD, PhysicalKeyboardKey.keyD, 'd'))?.dir, NavDir.right);
    expect((await press(LogicalKeyboardKey.keyD, PhysicalKeyboardKey.keyF, 'd'))?.dir, NavDir.right);
    // No other position counts: W, A and S positions that type other letters are plain keys.
    expect(await press(LogicalKeyboardKey.keyZ, PhysicalKeyboardKey.keyW, 'z'), isNull);
    expect(await press(LogicalKeyboardKey.keyQ, PhysicalKeyboardKey.keyA, 'q'), isNull);
    expect(await press(LogicalKeyboardKey.keyO, PhysicalKeyboardKey.keyS, 'o'), isNull);
    // Shift+A is still a command in Tasks, so Shift at that position is not Right either.
    await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect((await press(LogicalKeyboardKey.keyR, PhysicalKeyboardKey.keyD, 'R')), isNull);
    await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });
}
