import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show addTearDown;
import 'package:nvimos_poc/rpc/client.dart';
import 'package:nvimos_poc/state/nvim_launcher.dart';

import 'temp_dirs.dart';

/// A headless Neovim listening on a free TCP port, with the backend plugin loaded.
class TestNvim {
  TestNvim._(this.process, this.port, this.dir);

  final Process process;
  final int port;
  final Directory dir;

  /// NVIMOS_BACKEND, else a relay checkout next to this repo or a parent (as the app finds it).
  static String get backendDir =>
      findBackendDir(starts: [Directory.current.path]) ??
      '${Directory.current.parent.path}/relay'.replaceAll('\\', '/');

  static Future<int> freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  /// Start Neovim in [cwd] (default: a new temp dir).
  static Future<TestNvim> start({Directory? cwd}) async => startOn(await freePort(), cwd: cwd);

  /// Start Neovim on a given port.
  static Future<TestNvim> startOn(int port, {Directory? cwd}) async {
    final dir = cwd ?? keepForCleanup(await Directory.systemTemp.createTemp('nvimos_test_'));
    final p = await Process.start('nvim', [
      '--headless',
      '--clean',
      '-n',
      '-i',
      'NONE',
      '--listen',
      '127.0.0.1:$port',
      '--cmd',
      'set rtp^=$backendDir',
    ], workingDirectory: dir.path);
    p.stdout.drain<void>();
    p.stderr.drain<void>();
    final nvim = TestNvim._(p, port, dir);
    // Stopped when the test ends, also when it fails before its own stop(): a live Neovim locks
    // its folder, so the folder could not be deleted and the process would outlive the run.
    addTearDown(nvim.stop);
    return nvim;
  }

  /// Connect, retrying while Neovim starts.
  Future<NvimRpc> connect() async {
    final until = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      try {
        return await NvimRpc.connect('127.0.0.1', port);
      } on SocketException {
        if (DateTime.now().isAfter(until)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> stop() async {
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }
}

/// git in [dir] with a test identity; throws on failure. The fsmonitor is off: it starts a
/// background daemon per repo that outlives the test.
Future<String> git(Directory dir, List<String> args) async {
  final r = await Process.run('git', [
    '-c',
    'core.fsmonitor=false',
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test@example.com',
    '-c',
    'core.autocrlf=false',
    ...args,
  ], workingDirectory: dir.path);
  if (r.exitCode != 0) throw Exception('git ${args.join(' ')}: ${r.stderr}');
  return '${r.stdout}';
}

/// A temp repo on main with a.txt (5 lines) and b.txt, one commit.
Future<Directory> makeRepo() async {
  final d = keepForCleanup(await Directory.systemTemp.createTemp('nvimos_repo_'));
  await git(d, ['init', '-q', '-b', 'main']);
  for (final kv in {'user.name': 'Test', 'user.email': 'test@example.com', 'core.autocrlf': 'false', 'core.fsmonitor': 'false'}.entries) {
    await git(d, ['config', kv.key, kv.value]);
  }
  await File('${d.path}/a.txt').writeAsString('one\ntwo\nthree\nfour\nfive\n');
  await File('${d.path}/b.txt').writeAsString('bee\n');
  await git(d, ['add', '.']);
  await git(d, ['commit', '-q', '-m', 'first']);
  return d;
}
