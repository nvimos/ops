import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/preview.dart';
import 'package:ops_html/ops_html.dart' show htmlBuiltIn;
import 'package:ops_markdown/ops_markdown.dart' show markdownBuiltIn;
import 'package:nvimos_poc/ui/preview_pane.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'support/tooltip_semantics.dart';

void main() {
  testWidgets('a text file previews as numbered lines, a binary one says so and can be opened', (t) async {
    final files = {
      'a.txt': Uint8List.fromList(utf8.encode('alpha\nbeta\n')),
      'a.bin': Uint8List.fromList([1, 2, 0, 3]),
    };
    final state = PreviewState(root: () => 'C:/repo', read: (path, limit) async => files[path.substring('C:/repo/'.length)]!);
    addTearDown(state.dispose);
    String? launched;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: PreviewPane(state: state, onLaunch: (file, {program = false}) => launched = file)),
      ),
    );
    expect(find.text('Nothing highlighted.'), findsOneWidget);

    await state.load(['a.txt']);
    await t.pump();
    expect(find.text('a.txt'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);

    await state.load(['a.bin']);
    await t.pump();
    expect(find.text('alpha'), findsNothing);
    expect(find.text('binary file, 4 bytes'), findsOneWidget);
    expect(find.byTooltip('Open with the default app'), findsOneWidget);
    await t.tap(find.text('Open'));
    expect(launched, 'C:/repo/a.bin');
    await expectTooltipsInSemantics(t);
  });

  testWidgets('markdown is rendered, the switch shows its text, a link is followed with the pointer cursor', (t) async {
    final files = {'README.md': Uint8List.fromList(utf8.encode('# Title\n\n[the plan](PLAN.md)\n'))};
    final state = PreviewState(root: () => 'C:/repo', read: (path, limit) async => files[path.substring('C:/repo/'.length)]!);
    addTearDown(state.dispose);
    final links = <(String, String)>[];
    final picked = <bool>[];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: PreviewPane(
            state: state,
            onLink: (href, from) => links.add((href, from)),
            onRender: (v) {
              picked.add(v);
              state.rendered = v;
            },
          ),
        ),
      ),
    );
    expect(find.byType(RenderedSwitch), findsNothing, reason: 'no markdown shown yet');
    await state.load(['README.md']);
    await t.pump();
    expect(find.byType(RenderedSwitch), findsOneWidget);
    expect(find.text('Title', findRichText: true), findsOneWidget, reason: 'the heading, without its #');

    final link = find.text('the plan', findRichText: true);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: t.getCenter(link));
    await t.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    await t.tap(link);
    expect(links, [('PLAN.md', 'C:/repo/README.md')]);

    await t.tap(find.text('Text'));
    await t.pump();
    expect(picked, [false]);
    expect(find.text('# Title'), findsOneWidget, reason: 'the source line');
    await expectTooltipsInSemantics(t);
  }, skip: !markdownBuiltIn);

  testWidgets('HTML is drawn without its tags or scripts; a link comes resolved against the page folder', (t) async {
    const page = '<h1>Welcome</h1><script>alert(1)</script><p><a href="sub/next.html#x">next</a></p>';
    final state = PreviewState(root: () => 'C:/repo', read: (path, limit) async => Uint8List.fromList(utf8.encode(page)));
    addTearDown(state.dispose);
    final links = <(String, String)>[];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: PreviewPane(state: state, onLink: (href, from) => links.add((href, from)))),
      ),
    );
    await state.load(['docs/index.html']);
    await t.pump();
    expect(find.byType(RenderedSwitch), findsOneWidget);
    expect(find.text('Welcome', findRichText: true), findsOneWidget);
    expect(find.textContaining('alert', findRichText: true), findsNothing, reason: 'no script text');
    expect(find.byTooltip('Open with the default app'), findsOneWidget, reason: 'Open shows the real page');

    await t.tapOnText(find.textRange.ofSubstring('next'));
    await t.pump();
    expect(links.single.$2, 'C:/repo/docs/index.html');
    expect(Uri.parse(links.single.$1).removeFragment().toFilePath(windows: true), r'C:\repo\docs\sub\next.html');
    await expectTooltipsInSemantics(t);
  }, skip: !htmlBuiltIn);
}
