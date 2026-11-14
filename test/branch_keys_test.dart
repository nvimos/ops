import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/shell.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'support/nvim.dart';

/// Shift+C and `gb` in the whole window: Changes mode, the branch switcher focused, its list open.
/// Neovim runs in real time (runAsync); the widgets on the test clock.
void main() {
  testWidgets('Shift+C (also from Help) and gb open the branch switcher of Changes', (t) async {
    final (nvim, s) = (await t.runAsync(() async {
      final repo = await makeRepo();
      await git(repo, ['branch', 'dev']);
      final nvim = await TestNvim.start(cwd: repo);
      await nvim.connect().then((r) => r.close());
      final s = Session(port: nvim.port);
      await s.connect();
      return (nvim, s);
    }))!;
    await t.binding.setSurfaceSize(const Size(1400, 900));
    await t.pumpWidget(SessionScope(session: s, child: MaterialApp(theme: buildTheme(), home: const Shell())));
    Future<void> settle() async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100)); // the post-frame callbacks and the list chain over frames
      await t.pump(const Duration(milliseconds: 100));
    }

    Future<void> shiftC() async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'C');
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await settle();
    }

    int shown() => t.widget<IndexedStack>(find.byType(IndexedStack)).index!;
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    await settle();
    await t.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await t.pump();
    expect(shown(), Mode.help.index);

    await shiftC(); // from Help too
    expect(shown(), Mode.changes.index);
    expect(focused(), 'branch switcher');
    expect(find.text('dev'), findsOneWidget); // the list is open

    await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft); // Alt+2: Changes again, the keyboard on its list
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settle();
    expect(focused(), isNot('branch switcher'));
    expect(find.text('dev'), findsNothing); // the focus loss closed the list

    await t.sendKeyEvent(LogicalKeyboardKey.keyG, character: 'g');
    await t.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
    await settle();
    expect(focused(), 'branch switcher');
    expect(find.text('dev'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      s.dispose();
      await nvim.stop();
    });
  });
}
