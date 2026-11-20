import 'package:flutter/gestures.dart' show PointerDeviceKind, kBackMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/debug_bar.dart' show debugBarVisible;
import 'package:nvimos_poc/ui/mode_rail.dart' show Mode, ModeRail, RailState;
import 'package:nvimos_poc/ui/shell.dart';
import 'package:nvimos_poc/ui/theme.dart';

Widget shell(Session s) =>
    SessionScope(session: s, child: MaterialApp(theme: buildTheme(), home: const Shell()));

ModeRail rail(WidgetTester t) => t.widget<ModeRail>(find.byType(ModeRail));

Future<void> alt(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await t.sendKeyEvent(key);
  await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await t.pump();
}

void main() {
  testWidgets('a hidden mode is skipped at startup, by Alt+1..9 and by a step', (t) async {
    final s = Session(port: 1); // never connected: no sockets and no Neovim
    addTearDown(s.dispose);
    s.prefs.setStrings(RailState.hiddenKey, [Mode.pullRequest.name]);
    await t.pumpWidget(shell(s));
    await t.pump();

    expect(rail(t).modes, isNot(contains(Mode.pullRequest)));
    expect(rail(t).mode, Mode.changes, reason: 'the startup mode falls to the nearest visible one');

    await alt(t, LogicalKeyboardKey.digit1);
    expect(rail(t).mode, Mode.changes, reason: 'the first visible mode');
    await alt(t, LogicalKeyboardKey.digit2);
    expect(rail(t).mode, Mode.addIgnore, reason: 'Alt+2 is the second visible mode');
    await alt(t, LogicalKeyboardKey.bracketRight);
    expect(rail(t).mode, Mode.history, reason: 'the step skips the hidden mode too');
  });

  testWidgets('hiding the shown mode goes to its nearest visible neighbour', (t) async {
    final s = Session(port: 1);
    addTearDown(s.dispose);
    await t.pumpWidget(shell(s));
    await t.pump();
    expect(rail(t).mode, Mode.pullRequest);

    rail(t).onHide!(Mode.pullRequest);
    await t.pump();

    expect(rail(t).mode, Mode.changes, reason: 'the next mode in the rail');
    expect(rail(t).modes, isNot(contains(Mode.pullRequest)));
    expect(s.prefs.strings(RailState.hiddenKey), [Mode.pullRequest.name]);
  });

  testWidgets('the debug bar shows the place the back button would show, and back uses it', (t) async {
    debugBarVisible.value = false;
    addTearDown(() => debugBarVisible.value = false);
    final s = Session(port: 1);
    addTearDown(s.dispose);
    await t.pumpWidget(shell(s));
    await t.pump();

    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.pump();
    expect(find.text('Back:'), findsOneWidget);
    expect(find.text('Back to Pull request'), findsNothing);

    await alt(t, LogicalKeyboardKey.digit2); // Pull request -> Changes records a place
    expect(find.text('Back to Pull request'), findsOneWidget);

    // The mouse's back button: any hit test under the shell still passes the root Listener.
    await t.sendEventToBinding(
      const PointerDownEvent(buttons: kBackMouseButton, position: Offset(20, 20), kind: PointerDeviceKind.mouse),
    );
    await t.pump();
    expect(rail(t).mode, Mode.pullRequest);
    expect(find.text('Back to Pull request'), findsNothing);

    debugBarVisible.value = false;
    await t.pump(const Duration(milliseconds: 1)); // flush the debug bar's zero-delay refresh
  });
}

