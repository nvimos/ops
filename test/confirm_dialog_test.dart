import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/confirm_dialog.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  Future<bool?> open(WidgetTester t, {required void Function(bool) onResult}) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await confirm(
                context,
                title: 'Discard changes?',
                text: 'This hunk of a.txt.\nThis can\'t be undone.',
                okLabel: 'Discard',
                danger: true,
              ),
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    );
    await t.tap(find.text('ask'));
    await t.pumpAndSettle();
    return null;
  }

  testWidgets('the title and the text can be selected and copied; the buttons are not part of it', (t) async {
    final copied = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(t, onResult: (_) {});

    expect(find.descendant(of: find.byType(SelectionArea), matching: find.text('Discard changes?')), findsOneWidget);
    t.state<SelectableRegionState>(find.byType(SelectableRegion)).selectAll();
    await t.pump();
    Actions.invoke(t.element(find.text('Discard changes?')), CopySelectionTextIntent.copy); // what Ctrl+C does
    await t.pump();
    expect(copied, hasLength(1));
    expect(copied.single, contains('Discard changes?'));
    expect(copied.single, contains('This hunk of a.txt.'));
    expect(copied.single, contains("This can't be undone."));
    expect(copied.single, isNot(contains('Cancel'))); // the buttons stay out of the selection
    expect(copied.single, isNot(contains('Discard\n')));
  });

  testWidgets('Cancel gives false, the action gives true', (t) async {
    final results = <bool>[];
    await open(t, onResult: results.add);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.tap(find.text('ask'));
    await t.pumpAndSettle();
    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();
    expect(results, [false, true]);
  });
}
