import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/notices.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/error_view.dart';
import 'package:nvimos_poc/ui/notice_bar.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  test('the same message again is one notice with a count; another message replaces it', () {
    final n = Notices();
    addTearDown(n.dispose);
    n.show('boom');
    n.show('boom');
    n.show('boom');
    expect(n.current!.count, 3);
    n.show('other');
    expect(n.current!.message, 'other');
    expect(n.current!.count, 1);
  });

  testWidgets('a failed action shows in the bar; hovering keeps it open, leaving lets it go; Details shows the trace', (t) async {
    final session = Session();
    addTearDown(session.dispose);
    late BuildContext ctx;
    await t.pumpWidget(
      SessionScope(
        session: session,
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) {
              ctx = context;
              return Scaffold(body: const SizedBox.expand(), bottomNavigationBar: NoticeBar(notices: session.notices));
            },
          ),
        ),
      ),
    );
    expect(find.byType(SnackBar), findsNothing);

    const full = "NvimError(git.stage): fatal: pathspec 'x' did not match\nstack traceback:\n\t[C]: in ?";
    showActionError(ctx, full);
    await t.pump();
    expect(find.byType(SnackBar), findsNothing, reason: 'the bar, not a snackbar');
    expect(find.text("fatal: pathspec 'x' did not match"), findsOneWidget);
    expect(find.byTooltip('The full text, with the trace'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsOneWidget);

    // the mouse is over it: it outlives its lifetime
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.text("fatal: pathspec 'x' did not match")));
    await t.pump();
    await t.pump(const Duration(seconds: 20));
    expect(find.text("fatal: pathspec 'x' did not match"), findsOneWidget);

    // Details: the full text with the trace
    await t.tap(find.text('Details'));
    await t.pump();
    expect(find.textContaining('stack traceback'), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pump();

    // the mouse leaves: the time that was left runs out and it goes
    await mouse.moveTo(const Offset(1, 1));
    await t.pump();
    await t.pump(const Duration(seconds: 7));
    expect(find.text("fatal: pathspec 'x' did not match"), findsNothing);
  });

  testWidgets('a plain message has no Details button; the same failure twice shows a count', (t) async {
    final session = Session();
    addTearDown(session.dispose);
    late BuildContext ctx;
    await t.pumpWidget(
      SessionScope(
        session: session,
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) {
              ctx = context;
              return Scaffold(body: const SizedBox.expand(), bottomNavigationBar: NoticeBar(notices: session.notices));
            },
          ),
        ),
      ),
    );
    showActionError(ctx, 'not connected');
    showActionError(ctx, 'not connected');
    await t.pump();
    expect(find.text('Details'), findsNothing);
    expect(find.text('×2'), findsOneWidget);
    await t.pump(const Duration(seconds: 7));
  });
}
