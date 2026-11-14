import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/pr.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/pr_view.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'package:nvimos_poc/ui/widgets.dart';

void main() {
  testWidgets('Swap (label column) and Merge (in line with the fields) are on the line between the pickers', (t) async {
    final s = Session();
    final pr = PrState(s);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SizedBox(width: 400, child: PrPickers(pr: pr)),
        ),
      ),
    );
    final base = t.getRect(find.widgetWithText(Row, 'base').first);
    final head = t.getRect(find.widgetWithText(Row, 'head').first);
    final fields = t.getRect(find.byType(TextField).first);
    final swap = t.getCenter(find.byIcon(Icons.swap_vert));
    final merge = t.getRect(find.widgetWithText(SmallButton, 'merge'));

    // In the label column (left of the fields), vertically between the two pickers.
    expect(swap.dx, lessThan(fields.left));
    expect(swap.dy, greaterThan(base.bottom - 1));
    expect(swap.dy, lessThan(head.top + 1));
    // The merge actions: on the same line, starting where the fields start.
    expect(merge.center.dy, closeTo(swap.dy, 1));
    expect(merge.top, greaterThanOrEqualTo(base.bottom - 1));
    expect(merge.bottom, lessThanOrEqualTo(head.top + 1));
    expect(merge.left, closeTo(fields.left, 1));
    expect(t.widget<SmallButton>(find.byType(SmallButton)).onPressed, isNull); // no diff to merge
    pr.dispose();
    s.dispose();
  });
}
