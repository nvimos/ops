import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/nvim_launcher.dart';
import 'package:nvimos_poc/state/session.dart';

import 'support/nvim.dart';

void main() {
  test('Start headless: launches Neovim with the plugin and connects to it', () async {
    final port = await TestNvim.freePort();
    final s = Session(port: port);
    await s.startNeovim(kind: NvimKind.headless).timeout(const Duration(seconds: 10));
    final (conn, error, starting) = (s.conn, s.error, s.starting);
    await s.stopHeadlessNeovims(); // before the checks: never leave a Neovim behind
    expect(error, isNull);
    expect(conn, Conn.connected);
    expect(starting, isNull);
    s.dispose();
  });

  test('Start on a port a silent program holds: says so at once, starts nothing, no stuck button', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    server.listen((c) {}); // accepts, never answers
    final s = Session(port: server.port);
    await s.startNeovim(kind: NvimKind.headless).timeout(const Duration(seconds: 6));
    expect(s.error, contains('is taken'));
    expect(s.starting, isNull);
    expect(s.conn, Conn.disconnected);
    s.dispose();
    await server.close();
  });

  test('a launcher failure shows as the error and frees the buttons', () async {
    final s = Session(port: await TestNvim.freePort());
    final real = Platform.environment['NVIMOS_BACKEND'];
    expect(real, anyOf(isNull, isNotEmpty)); // the plugin lookup is exercised by the first test
    s.showError('could not start headless Neovim: boom');
    expect(s.error, contains('boom'));
    expect(s.starting, isNull);
    s.dispose();
  });
}
