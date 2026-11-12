import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/list_pair.dart';
import 'package:nvimos_poc/ui/list_pair_view.dart';

void main() {
  const many = (rows: 40, row: 26.0, pad: 8.0), few = (rows: 10, row: 24.0, pad: 0.0);

  test('the dominant list takes the rest; the other 6 rows, or 3 when they compete', () {
    final p = ListPair();
    expect(pairHeights(p, 2000, [many, few]), [null, 6 * 24.0]);
    expect(pairHeights(p, 600, [many, few]), [null, 3 * 24.0]);
    p.toggleDominant(1);
    expect(pairHeights(p, 2000, [many, few]), [6 * 26.0 + 8, null]);
  });

  test('folding: a folded list gets 0, the other the rest; a folded dominant hands the room on', () {
    final p = ListPair();
    p.toggleCollapsed(0);
    expect(p.dominant, 1);
    expect(pairHeights(p, 600, [many, few]), [0, null]);
    p.toggleCollapsed(1);
    expect(pairHeights(p, 600, [many, few]), [0, 0]);
    p.toggleDominant(0);
    expect(p.collapsed, [false, true]); // the list that gets the room unfolds
  });

  test('collapse all keeps the selected file\'s folder', () {
    expect(foldAll(['a/x', 'a/y', 'b/z', 'top'], keep: 'b/z'), {'a'});
  });
}
