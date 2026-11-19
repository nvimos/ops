import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/status_bar.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  testWidgets('the hot buttons call reload and restart', (tester) async {
    var reload = 0;
    var restart = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: HotButtons(onReload: () => reload++, onRestart: () => restart++),
      ),
    ));

    await tester.tap(find.byIcon(Icons.bolt));
    await tester.tap(find.byIcon(Icons.restart_alt));
    expect(reload, 1);
    expect(restart, 1);
  });
}
