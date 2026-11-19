import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/main.dart' show launchTarget, startupFolder;
import 'package:nvimos_poc/state/prefs.dart';

import 'support/temp_dirs.dart';

void main() {
  test('launchTarget: an existing directory is opened locally, anything else is the address', () async {
    final dir = keepForCleanup(await Directory.systemTemp.createTemp('nvimos_target_'));

    expect(launchTarget([dir.path], isDir: (p) => Directory(p).existsSync()), (dir: dir.absolute.path, address: null));
    expect(launchTarget(['127.0.0.1:7000'], isDir: (_) => false), (dir: null, address: '127.0.0.1:7000'));
    expect(launchTarget([], envAddress: 'env:2'), (dir: null, address: 'env:2'));
  });

  test('startupFolder: local by default, the last local folder that still exists, else the cwd', () {
    const recents = [
      Recent(BackendKind.nvim, '127.0.0.1:6666'),
      Recent(BackendKind.local, 'C:/gone'),
      Recent(BackendKind.local, 'C:/repo'),
    ];
    expect(startupFolder(recents, 'C:/cwd', isDir: (p) => p == 'C:/repo'), 'C:/repo');
    expect(startupFolder(recents, 'C:/cwd', isDir: (_) => false), 'C:/cwd');
    expect(startupFolder(const [], 'C:/cwd', isDir: (_) => true), 'C:/cwd');
  });
}
