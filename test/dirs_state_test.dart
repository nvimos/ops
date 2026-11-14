import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/dirs.dart';
import 'package:nvimos_poc/state/session.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

String norm(String p) => p.replaceAll('\\', '/').toLowerCase();

void main() {
  test('lists recent dirs, filters, and :cd moves the Active Directory to another repo', () async {
    final one = await makeRepo();
    final two = await makeRepo();
    final nvim = await TestNvim.start(cwd: one);
    final rpc = await nvim.connect();
    await rpc.request('nvim_set_vvar', ['oldfiles', ['${two.path}/a.txt'.replaceAll('\\', '/')]]);
    await rpc.close();

    final s = Session(port: nvim.port);
    await s.connect();
    final d = DirsState(s);
    await until(() => d.dirs != null);
    expect(d.dirs!.source, 'oldfiles');
    expect(d.shown.map(norm), [norm(two.path)]);

    d.setFilter('no such thing');
    expect(d.shown, isEmpty);
    d.setFilter('');

    expect(await d.pick(two.path), isNull);
    await until(() => norm(s.repo!.root ?? '') == norm(two.path));
    expect(norm(d.active!), norm(two.path));

    d.dispose();
    s.dispose();
    await nvim.stop();
  });

  test('New Neovim per directory: starts one in the dir and connects to it', () async {
    final one = await makeRepo();
    final two = await makeRepo();
    final first = await TestNvim.start(cwd: one);
    await first.connect().then((r) => r.close());
    TestNvim? second;

    final s = Session(port: first.port);
    await s.connect();
    final d = DirsState(
      s,
      launch: (dir, address, root) async {
        expect(norm(root), norm(TestNvim.backendDir));
        second = await TestNvim.startOn(int.parse(address.split(':').last), cwd: Directory(dir));
      },
    );
    d.toggleNewNeovim();
    expect(await d.pick(two.path), isNull);
    await until(() => s.conn == Conn.connected && s.address.endsWith(':${second?.port}'), timeout: const Duration(seconds: 15));
    await until(() => norm(s.repo?.root ?? '') == norm(two.path));

    d.dispose();
    s.dispose();
    await second?.stop();
    await first.stop();
  });
  test('opening target of the Active Directory: a branch, else changes, else tasks', () async {
    final repo = await makeRepo();
    final nvim = await TestNvim.start(cwd: repo);
    final s = Session(port: nvim.port);
    await s.connect();
    final d = DirsState(s);

    expect(await d.openingTarget(), OpenTarget.tasks); // main only, clean

    await File('${repo.path}/a.txt').writeAsString('changed\n');
    expect(await d.openingTarget(), OpenTarget.changes);

    await git(repo, ['branch', 'feature']);
    expect(await d.openingTarget(), OpenTarget.pullRequest);

    d.dispose();
    s.dispose();
    await nvim.stop();
  });
}
