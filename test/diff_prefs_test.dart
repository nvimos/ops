import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/diff_prefs.dart';
import 'package:nvimos_poc/state/prefs.dart';

void main() {
  test('wrapping and hunk headers are kept in the prefs; the layout is not', () {
    final prefs = Prefs.memory();
    final first = DiffPrefs(prefs);
    expect((first.wrap, first.hunkHeaders), (true, true)); // the defaults
    first.toggleWrap();
    first.toggleHunkHeaders();
    first.setLayout(DiffLayout.sideBySide);

    final next = DiffPrefs(prefs); // the next run reads the same prefs
    expect((next.wrap, next.hunkHeaders), (false, false));
    expect(next.layout, DiffLayout.unified);
    next.toggleWrap();
    expect(DiffPrefs(prefs).wrap, true);
  });
}
