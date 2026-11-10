import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/rpc/msgpack.dart';

Object? roundTrip(Object? v) => MsgDecoder().add(msgEncode(v)).single;

void main() {
  test('round-trips scalars at every size boundary', () {
    for (final v in <Object?>[
      null,
      true,
      false,
      0,
      1,
      127,
      128,
      255,
      256,
      65535,
      65536,
      4294967295,
      4294967296,
      -1,
      -32,
      -33,
      -128,
      -129,
      -32768,
      -32769,
      -2147483648,
      -2147483649,
      1.5,
      -0.25,
      '',
      'a',
      'x' * 31,
      'x' * 32,
      'x' * 300,
      'x' * 70000,
      'æøå ✓',
    ]) {
      expect(roundTrip(v), v, reason: '$v');
    }
  });

  test('round-trips lists, maps and bin', () {
    final v = {
      'list': [
        1,
        'two',
        null,
        [3],
      ],
      'big': List.generate(20, (i) => i),
      'map': {for (var i = 0; i < 20; i++) 'k$i': i},
      'bin': Uint8List.fromList([1, 2, 3]),
    };
    expect(roundTrip(v), v);
  });

  test('decodes values split across chunks', () {
    final bytes = [
      ...msgEncode([
        0,
        1,
        'nvim_eval',
        ['1+1'],
      ]),
      ...msgEncode('second'),
    ];
    final d = MsgDecoder();
    final out = <Object?>[];
    for (final b in bytes) {
      out.addAll(d.add([b]));
    }
    expect(out, [
      [
        0,
        1,
        'nvim_eval',
        ['1+1'],
      ],
      'second',
    ]);
  });

  test('Neovim handle ext types decode to their integer id', () {
    final ext = MsgExt(0, msgEncode(7));
    expect(roundTrip(ext), 7);
    final other = MsgExt(9, Uint8List.fromList([1, 2]));
    expect(roundTrip(other), other);
  });
}
