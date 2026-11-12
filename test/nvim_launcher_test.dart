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
    await File('${root.path}/nvimos-poc-backend/plugin/nvimos.lua').create(recursive: true);
    final deep = await Directory('${root.path}/front/build/Release').create(recursive: true);
    final found = findBackendDir(env: {}, starts: [deep.path]);
    expect(found, '${root.absolute.path}/nvimos-poc-backend'.replaceAll(r'\', '/'));
    expect(findBackendDir(env: {}, starts: [Directory.systemTemp.path]), anyOf(isNull, isNot(found)));
  });

  test('findBackendDir finds a relay clone and skips a relay folder without the plugin', () async {
    final root = await Directory.systemTemp.createTemp('nvimos_launch_');
    addTearDown(() => root.delete(recursive: true));
    final deep = await Directory('${root.path}/ops/build/Release').create(recursive: true);
    await Directory('${root.path}/ops/relay').create();
    expect(findBackendDir(env: {}, starts: [deep.path]), isNot(endsWith('/ops/relay')));
    await File('${root.path}/relay/plugin/nvimos.lua').create(recursive: true);
    expect(findBackendDir(env: {}, starts: [deep.path]), '${root.absolute.path}/relay'.replaceAll(r'\', '/'));
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

  test('nvimCommand: console through start, nvim-qt passes args after --, headless detached', () {
    final args = nvimArgs('127.0.0.1:1', 'C:/b');
    List<String> cmd(NvimKind k) {
      final (exe, a) = nvimCommand(k, '127.0.0.1:1', 'C:/b', qt: ['-qt']);
      return [exe, ...a];
    }

    expect(cmd(NvimKind.console), ['cmd', '/c', 'start', 'nvimos nvim', 'nvim', ...args]);
    expect(cmd(NvimKind.qt), ['nvim-qt', '-qt', '--', ...args]);
    expect(cmd(NvimKind.headless), ['nvim', '--headless', ...args]);
  });

  test('qtArgs: dark mode, and the config stylesheet when it exists', () {
    final env = {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'};
    expect(qtArgs(env: env, exists: (_) => true), [
      '-platform',
      'windows:darkmode=1',
      '-stylesheet',
      r'C:\Users\u\AppData\Local\nvim\nvim-qt.qss',
    ]);
    expect(qtArgs(env: env, exists: (_) => false), ['-platform', 'windows:darkmode=1']);
  });

  test('qtOpenArgs: the file at its line, after the nvim-qt options', () {
    expect(qtOpenArgs('C:/m/backlog/t.md', 3, qt: ['-qt']), ['-qt', '--', '+3', 'C:/m/backlog/t.md']);
  });

  test('stopHeadlessScript only matches headless nvim.exe of this user', () {
    expect(stopHeadlessScript, contains("Name='nvim.exe'"));
    expect(stopHeadlessScript, contains("-match '--headless'"));
    expect(stopHeadlessScript, contains('GetOwner'));
  });
}
