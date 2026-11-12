import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/ui/reveal.dart';

void main() {
  testWidgets('revealRange scrolls the least that shows the row, in either direction', (t) async {
    final c = ScrollController();
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 100,
            child: ListView.builder(controller: c, itemExtent: 20, itemCount: 50, itemBuilder: (_, i) => Text('$i')),
          ),
        ),
      ),
    );
    revealRange(c, 0, 20);
    expect(c.offset, 0); // already visible
    revealRange(c, 200, 20); // row 10, below the 100 px view: it ends at the bottom edge
    expect(c.offset, 120);
    revealRange(c, 60, 20); // row 3, above the view: it starts at the top edge
    expect(c.offset, 60);
    revealRange(c, 100, 20); // row 5, inside 60..160
    expect(c.offset, 60);
    c.dispose();
  });
}
