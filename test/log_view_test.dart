import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/local/browser.dart';
import 'package:nvimos_poc/state/log_state.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/log_view.dart';
import 'support/tooltip_semantics.dart';

void main() {
  testWidgets('a log row opens to its detail', (tester) async {
    final log = LogState(Session());
    addTearDown(log.dispose);
    log.addScan(const ScanReport(
      directory: 'C:/fake',
      depth: 3,
      visited: 4,
      found: 1,
      skipped: 2,
      elapsed: Duration(milliseconds: 20),
      slowest: [],
      widest: [],
      stopped: false,
    ));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LogView(log: log))));
    expect(find.textContaining('scanned C:/fake'), findsOneWidget);
    await tester.tap(find.textContaining('scanned C:/fake'));
    await tester.pump();
    expect(find.textContaining('origin: RepoBrowser.scan'), findsOneWidget);
    await expectTooltipsInSemantics(tester);
  });
}
