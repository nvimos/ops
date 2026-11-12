import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/diff_prefs.dart';

void main() {
  testWidgets('Up / Down scroll 3 lines, with Shift 10; the ends stop it', (t) async {
    final scroll = DiffScroll();
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          height: 200,
          child: ListView.builder(
            controller: scroll,
            itemExtent: DiffScroll.lineHeight,
            itemCount: 100,
            itemBuilder: (_, i) => Text('$i'),
          ),
        ),
      ),
    );
    expect(DiffScroll.step, 3);
    scroll.byLines(DiffScroll.step);
    expect(scroll.offset, 3 * DiffScroll.lineHeight);
    scroll.byLines(DiffScroll.bigStep);
    expect(scroll.offset, (3 + 10) * DiffScroll.lineHeight);
    scroll.byLines(-2 * DiffScroll.bigStep);
    expect(scroll.offset, 0); // not above the top
    scroll.byLines(1 << 20);
    expect(scroll.offset, scroll.position.maxScrollExtent);
    scroll.dispose();
  });
}
