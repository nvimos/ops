import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/ui/key_sequence.dart';

void main() {
  test('single keys, two-key sequences, unknown keys, and a prefix that times out', () async {
    final log = <String>[];
    final k = KeySequence({
      'v': () => log.add('v'),
      'gs': () => log.add('gs'),
      ']f': () => log.add(']f'),
    }, timeout: const Duration(milliseconds: 20));

    expect(k.press('v'), isTrue);
    expect(k.press('g'), isTrue); // waits for the second key
    expect(k.press('s'), isTrue);
    expect(k.press('x'), isFalse);
    expect(k.press(']'), isTrue);
    expect(k.press('x'), isFalse); // ]x is no command; the prefix is gone
    expect(k.press('g'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(k.press('s'), isFalse); // too late: a plain s
    expect(k.press(null), isFalse);
    expect(log, ['v', 'gs']);
    k.dispose();
  });
}
