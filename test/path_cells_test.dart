import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/ui/path_cells.dart';

void main() {
  test('fitTail keeps a text that fits', () {
    expect(fitTail('lib/ui/', 7), 'lib/ui/');
    expect(fitTail('lib/ui/', 20), 'lib/ui/');
  });

  test('fitTail drops the start of a long folder, not the end', () {
    expect(fitTail('lib/ui/widgets/', 9), '…widgets/');
    expect(fitTail('lib/ui/widgets/', 1), '…');
    expect(fitTail('lib/ui/widgets/', 0), '…');
  });
}
