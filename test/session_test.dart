import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/session.dart';

import 'support/nvim.dart';

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 8)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw StateError('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('connects, follows the cursor, connects again on retry after Neovim restarts', () async {
    final repo = await makeRepo();
    var nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    expect(s.conn, Conn.connected);
    expect(s.repo!.head, 'main');

    await s.backend!.open('a.txt', 3);
    await until(() => s.cursor?.row == 3 && s.cursor!.name.endsWith('a.txt'));

    final port = nvim.port;
    await nvim.stop();
    await until(() => s.conn != Conn.connected);
    expect(s.error, isNotNull);

    // Same port again: no retry of its own, the user's Retry connects.
    nvim = await TestNvim.startOn(port, cwd: repo);
    await nvim.connect().then((r) => r.close());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(s.conn, Conn.disconnected);
    await s.connect();
    expect(s.conn, Conn.connected);
    s.dispose();
    await nvim.stop();
  });

  test('a wrong address reports an error and tries only once', () async {
    final port = await TestNvim.freePort();
    final s = Session(port: port);
    var connecting = 0;
    s.addListener(() => connecting += s.conn == Conn.connecting ? 1 : 0);
    await s.connect();
    expect(s.conn, Conn.disconnected);
    expect(s.error, contains('no Neovim listening'));
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(connecting, 1);
    s.dispose();
  });
}
