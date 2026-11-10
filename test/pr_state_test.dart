import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/pr.dart';
import 'package:nvimos_poc/state/session.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

void main() {
  test('picks main and the newest other branch, loads commits and diff, refreshes on git hints', () async {
    final repo = await makeRepo();
    await git(repo, ['checkout', '-q', '-b', 'agent/x']);
    await File('${repo.path}/a.txt').writeAsString('one\nTWO\nthree\nfour\nfive\n');
    await git(repo, ['commit', '-q', '-am', 'agent edit']);
    await git(repo, ['checkout', '-q', 'main']);

    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final pr = PrState(s);
    await until(() => !pr.loading && pr.diff != null);

    expect([pr.base, pr.head], ['main', 'agent/x']);
    expect(pr.commits.single.subject, 'agent edit');
    expect(pr.selected, 'a.txt');
    expect(pr.selectedFile!.additions, 1);

    // An agent commits more on its branch: the view follows without a manual refresh.
    await git(repo, ['checkout', '-q', 'agent/x']);
    await File('${repo.path}/c.txt').writeAsString('new\n');
    await git(repo, ['add', 'c.txt']);
    await git(repo, ['commit', '-q', '-m', 'agent adds c']);
    await until(() => pr.commits.length == 2 && pr.diff!.files.length == 2);

    pr.swap();
    await until(() => !pr.loading && pr.base == 'agent/x');
    expect(pr.commits, isEmpty);

    pr.dispose();
    s.dispose();
    await nvim.stop();
  });
}
