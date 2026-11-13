import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/pr.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/pr_view.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'package:nvimos_poc/ui/widgets.dart';

void main() {
  testWidgets('the swap button is in the middle of the line, the merge actions to its right', (t) async {
    final s = Session();
    final pr = PrState(s);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 300, child: MergeActions(pr: pr)),
          ),
        ),
      ),
    );
    final line = t.getRect(find.byType(MergeActions));
    final swap = t.getCenter(find.byIcon(Icons.swap_vert));
    expect(swap.dx, closeTo(line.center.dx, 0.5));
    final merge = t.getRect(find.widgetWithText(SmallButton, 'Merge'));
    expect(merge.left, greaterThan(swap.dx));
    expect(t.widget<SmallButton>(find.byType(SmallButton)).onPressed, isNull); // no diff to merge
    pr.dispose();
    s.dispose();
  });
}
