import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/debug_bar.dart';
import 'package:nvimos_poc/ui/shell.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  _roles();
  _clicks();
  testWidgets('the bug button in the status bar shows the debug bar: focus, mode and last key', (t) async {
    final s = Session(port: 1); // never connected: no sockets on the fake clock
    await t.pumpWidget(SessionScope(session: s, child: MaterialApp(theme: buildTheme(), home: const Shell())));
    await t.pump();
    expect(find.byType(DebugBar), findsNothing);

    await t.tap(find.byIcon(Icons.bug_report_outlined));
    await t.pump();
    expect(find.byType(DebugBar), findsOneWidget);
    String shown() => [
      for (final w in t.widgetList<Text>(find.descendant(of: find.byType(DebugBar), matching: find.byType(Text)))) w.data,
    ].join('|');
    expect(shown(), contains('Focus:|Pull request')); // the shell's node: the mode's name, not a class

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump(const Duration(milliseconds: 10));
    expect(shown(), contains('Key:|Arrow Right'));
    expect(shown().split('|').length, greaterThan(2)); // one item per line, not one long line

    // The mouse is reported too: each button down and up, and the wheel.
    final at = t.getTopLeft(find.byType(DebugBar)) + const Offset(30, 30); // on the focus box, not the network monitor
    for (final (button, name) in [(kPrimaryButton, 'Left'), (kMiddleMouseButton, 'Middle'), (kSecondaryButton, 'Right')]) {
      final g = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: button);
      await g.down(at);
      await t.pump(const Duration(milliseconds: 10));
      expect(shown(), contains('Mouse:|$name down'));
      await g.up();
      await t.pump(const Duration(milliseconds: 10));
      expect(shown(), contains('Mouse:|$name up'));
    }
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 40)));
    await t.pump(const Duration(milliseconds: 10));
    expect(shown(), contains('Mouse:|Wheel down'));

    await t.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b'); // the key does the same as the button
    await t.pump(const Duration(milliseconds: 10));
    expect(find.byType(DebugBar), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
    await t.pump();
    expect(find.byType(DebugBar), findsOneWidget);

    await t.tap(find.byIcon(Icons.bug_report_outlined));
    await t.pump();
    expect(find.byType(DebugBar), findsNothing);
    debugBarVisible.value = false;
    s.dispose();
  });
}

void _clicks() {
  testWidgets('a click or a wheel step makes the bar read the focus and the mode state again', (t) async {
    var clicked = 0;
    final other = FocusNode(debugLabel: 'head picker');
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => clicked++, // state changes, no rebuild above, no focus change
                child: const SizedBox(key: ValueKey('box'), width: 100, height: 40),
              ),
              Focus(
                focusNode: other,
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: other.requestFocus, child: const SizedBox(key: ValueKey('field'), width: 100, height: 40)),
              ),
              DebugBar(pane: () => '', info: () => ['Clicks: $clicked']),
            ],
          ),
        ),
      ),
    );
    String shown() => [
      for (final w in t.widgetList<Text>(find.descendant(of: find.byType(DebugBar), matching: find.byType(Text)))) w.data,
    ].join('|');
    expect(shown(), contains('Clicks:|0'));

    await t.tap(find.byKey(const ValueKey('box')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(shown(), contains('Clicks:|1')); // read again after the click

    await t.tap(find.byKey(const ValueKey('field')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(shown(), contains('Focus:|Head revision field')); // the focus moved by the click
    other.dispose();
  });
}

void _roles() {
  testWidgets('uiRole names the focused element by what it is in the interface', (t) async {
    final base = FocusNode(debugLabel: 'base picker');
    final shell = FocusNode(debugLabel: 'shell');
    final plain = FocusNode();
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Focus(
          focusNode: shell,
          child: Column(
            children: [
              Focus(focusNode: base, child: const SizedBox()),
              Focus(focusNode: plain, child: const SizedBox()),
            ],
          ),
        ),
      ),
    );
    base.requestFocus();
    await t.pump();
    expect(uiRole(base, pane: 'Commits list'), 'Base revision field'); // its own role wins
    plain.requestFocus();
    await t.pump();
    expect(uiRole(plain, pane: 'Commits list'), 'Commits list'); // under the shell: the mode's pane
    expect(uiRole(null, pane: 'x'), 'nothing');
    expect(focusRoles.keys, containsAll(['shell', 'changes', 'base picker', 'head picker', 'commit message']));
  });

  testWidgets('the debug bar is three lines high: items stack three to a column, then a new column', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: DebugBar(pane: () => 'Commits list', info: () => ['Mode: A', 'File: b', 'Hunk: c']),
          ),
        ),
      ),
    );
    Offset at(String text) => t.getTopLeft(find.text(text));
    double colon(String label) => t.getTopRight(find.text(label)).dx;
    // Items: Focus, Mode, File, Hunk, Key -> columns [Focus, Mode, File] and [Hunk, Key].
    final focus = at('Focus:'), mode = at('Mode:'), file = at('File:');
    final hunk = at('Hunk:');
    expect(mode.dy, greaterThan(focus.dy));
    expect(file.dy, greaterThan(mode.dy));
    expect(hunk.dx, greaterThan(focus.dx)); // the fourth item starts the next column
    expect(hunk.dy, focus.dy);
    // The colons of a column are on one vertical line, and so are its values.
    expect(colon('Mode:'), colon('Focus:'));
    expect(colon('File:'), colon('Focus:'));
    expect(colon('Key:'), colon('Hunk:'));
    expect(at('A').dx, at('nothing').dx);
    expect(at('b').dx, at('nothing').dx);
    expect(t.getSize(find.byType(DebugBar)).height, lessThan(70));
  });
}
