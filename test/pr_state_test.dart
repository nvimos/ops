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

  test('narrows to one commit and back; takes any revision; next/previous file in tree order', () async {
    final repo = await makeRepo();
    await git(repo, ['checkout', '-q', '-b', 'agent/x']);
    await File('${repo.path}/a.txt').writeAsString('one\nTWO\nthree\nfour\nfive\n');
    await git(repo, ['commit', '-q', '-am', 'edit a']);
    await Directory('${repo.path}/sub').create();
    await File('${repo.path}/sub/c.txt').writeAsString('new\n');
    await git(repo, ['add', '.']);
    await git(repo, ['commit', '-q', '-m', 'add sub/c']);
    await git(repo, ['checkout', '-q', 'main']);

    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final pr = PrState(s);
    await until(() => !pr.loading && pr.diff != null);
    expect(pr.diff!.files.map((f) => f.path), unorderedEquals(['a.txt', 'sub/c.txt']));

    // One commit: only its file; the commit list keeps the whole range.
    final first = pr.commits.firstWhere((c) => c.subject == 'edit a');
    pr.narrow(first);
    await until(() => !pr.loading && pr.diff!.files.length == 1);
    expect(pr.diff!.files.single.path, 'a.txt');
    expect(pr.commits.length, 2);
    pr.narrow(first); // the same commit again: back to the full range
    await until(() => !pr.loading && pr.diff!.files.length == 2);
    expect(pr.narrowed, isNull);

    // Folders first in tree order: '' (a.txt) then sub/.
    pr.select('a.txt');
    pr.selectNext(1);
    expect(pr.selected, 'sub/c.txt');
    pr.selectNext(1);
    expect(pr.selected, 'sub/c.txt');
    pr.toggleAllDirs();
    expect(pr.collapsedDirs, isEmpty); // the selected file's folder stays open; the root has none
    pr.select('a.txt');
    pr.toggleAllDirs();
    expect(pr.collapsedDirs, {'sub'});

    // Any revision git accepts.
    pr.pick(base: 'agent/x~1', head: 'agent/x');
    await until(() => !pr.loading && pr.base == 'agent/x~1');
    expect(pr.error, isNull);
    expect(pr.commits.single.subject, 'add sub/c');

    pr.pick(base: 'no-such-rev');
    await until(() => !pr.loading && pr.error != null);
    expect(pr.base, 'no-such-rev');

    pr.dispose();
    s.dispose();
    await nvim.stop();
  });
}
