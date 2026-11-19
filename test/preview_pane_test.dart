import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/preview.dart';
import 'package:nvimos_poc/ui/preview_pane.dart';
import 'package:nvimos_poc/ui/theme.dart';

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
  });
}
