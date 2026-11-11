import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/nvim_launcher.dart';

void main() {
  test('findBackendDir takes NVIMOS_BACKEND first', () {
    expect(findBackendDir(env: {'NVIMOS_BACKEND': r'C:\x\backend'}, starts: []), 'C:/x/backend');
  });

  test('findBackendDir finds the checkout next to a parent folder', () async {
    final root = await Directory.systemTemp.createTemp('nvimos_launch_');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/nvimos-poc-backend').create();
    final deep = await Directory('${root.path}/front/build/Release').create(recursive: true);
    final found = findBackendDir(env: {}, starts: [deep.path]);
    expect(found, '${root.absolute.path}/nvimos-poc-backend'.replaceAll(r'\', '/'));
    expect(findBackendDir(env: {}, starts: [Directory.systemTemp.path]), anyOf(isNull, isNot(found)));
  });

  test('nvimArgs listens and loads the plugin after the config, like make nvim', () {
    expect(nvimArgs('127.0.0.1:6666', 'C:/b'), [
      '--listen',
      '127.0.0.1:6666',
      '-c',
      'set rtp^=C:/b',
      '-c',
      'runtime plugin/nvimos.lua',
    ]);
  });
}
