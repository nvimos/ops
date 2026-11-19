import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/main.dart' show launchTarget;

import 'support/temp_dirs.dart';

void main() {
  test('launchTarget: an existing directory is opened locally, anything else is the address', () async {
    final dir = keepForCleanup(await Directory.systemTemp.createTemp('nvimos_target_'));

    expect(launchTarget([dir.path], isDir: (p) => Directory(p).existsSync()), (dir: dir.absolute.path, address: null));
    expect(launchTarget(['127.0.0.1:7000'], isDir: (_) => false), (dir: null, address: '127.0.0.1:7000'));
    expect(launchTarget([], envAddress: 'env:2'), (dir: null, address: 'env:2'));
  });
}
