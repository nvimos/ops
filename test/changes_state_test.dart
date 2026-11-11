import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/session.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

void main() {
  test('lists changes, stages a hunk, commits, follows edits made in Neovim', () async {
    final repo = await makeRepo();
    final lines = List.generate(12, (i) => 'line ${i + 1}');
    await File('${repo.path}/a.txt').writeAsString('${lines.join('\n')}\n');
    await git(repo, ['commit', '-q', '-am', 'twelve']);
    lines[0] = 'LINE 1';
    lines[9] = 'LINE 10';
    await File('${repo.path}/a.txt').writeAsString('${lines.join('\n')}\n');

    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.diff != null);
    expect(st.selected, 'a.txt');
    expect(st.diff!.hunks.length, 2);

    expect(await st.act((b) => b.stageHunk('a.txt', st.diff!.hunks.first)), isNull);
    await until(() => st.staged.length == 1 && st.unstaged.length == 1);

    expect(await st.commit('first hunk'), isNull);
    await until(() => st.staged.isEmpty);
    expect((await git(repo, ['log', '-1', '--format=%s'])).trim(), 'first hunk');

    // Save a new file from Neovim: the list picks it up from the write hint.
    await s.backend!.rpc.request('nvim_command', ['edit new.txt']);
    await s.backend!.rpc.request('nvim_buf_set_lines', [
      0,
      0,
      -1,
      false,
      ['hello'],
    ]);
    await s.backend!.rpc.request('nvim_command', ['write']);
    await until(() => st.unstaged.any((f) => f.path == 'new.txt'));

    st.dispose();
    s.dispose();
    await nvim.stop();
  });

  test('stage all, unstage a file, stage and unstage the selected hunk; file kinds', () async {
    final repo = await makeRepo();
    await File('${repo.path}/a.txt').writeAsString('one\nTWO\nthree\nfour\nfive\n');
    await File('${repo.path}/c.txt').writeAsString('new\n');

    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.unstaged.length == 2);
    expect(fileKind(st.unstaged.firstWhere((f) => f.path == 'c.txt'), staged: false), 'untracked');

    expect(await st.moveAll(staged: false), isNull);
    await until(() => st.staged.length == 2 && st.unstaged.isEmpty);
    expect(fileKind(st.staged.firstWhere((f) => f.path == 'c.txt'), staged: true), 'added');

    expect(await st.moveFile('c.txt', staged: true), isNull);
    await until(() => st.staged.length == 1);

    st.select('a.txt', staged: true);
    await until(() => st.diff != null && st.selectedStaged);
    expect(await st.toggleHunk(st.diff!.hunks.single), isNull);
    await until(() => !st.staged.any((f) => f.path == 'a.txt'));

    expect(await st.openLine(2, isOld: true), isNull); // deletions have no line in the work tree

    // Keys: j/k walk the files in list order; ]c makes a hunk current; s stages it; u does
    // nothing on the unstaged side.
    await until(() => st.unstaged.length == 2); // a.txt (unstaged again) and c.txt
    st.select('a.txt', staged: false);
    await until(() => st.diff != null && st.diff!.hunks.isNotEmpty);
    st.moveSelection(1);
    expect(st.selected, 'c.txt');
    st.moveSelection(-1);
    expect(st.selected, 'a.txt');
    await until(() => st.diff != null && st.diff!.hunks.isNotEmpty);
    st.moveHunk(1);
    expect(st.hunk, 0);
    expect(await st.unstageCurrent(), isNull);
    expect(st.staged, isEmpty);
    expect(await st.stageCurrent(), isNull);
    await until(() => st.staged.any((f) => f.path == 'a.txt'));

    st.dispose();
    s.dispose();
    await nvim.stop();
  });
}
