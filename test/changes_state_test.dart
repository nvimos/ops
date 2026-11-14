import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/backend.dart' show CheckoutHow;
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

    expect(await st.act('stageHunk', (b) => b.stageHunk('a.txt', st.diff!.hunks.first)), isNull);
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

  test('a folder row stages and unstages the files directly in it', () async {
    final repo = await makeRepo();
    await Directory('${repo.path}/src/deep').create(recursive: true);
    await File('${repo.path}/src/a.txt').writeAsString('a\n');
    await File('${repo.path}/src/b.txt').writeAsString('b\n');
    await File('${repo.path}/src/deep/c.txt').writeAsString('c\n');
    await File('${repo.path}/top.txt').writeAsString('t\n');

    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.unstaged.length == 4);

    expect(await st.moveDir('src', staged: false), isNull);
    await until(() => st.staged.length == 2);
    expect({for (final f in st.staged) f.path}, {'src/a.txt', 'src/b.txt'});
    expect({for (final f in st.unstaged) f.path}, {'src/deep/c.txt', 'top.txt'});

    expect(await st.moveDir('src', staged: true), isNull);
    await until(() => st.staged.isEmpty && st.unstaged.length == 4);

    st.dispose();
    s.dispose();
    await nvim.stop();
  });

  test('switching branches: lists the branches, names the files a checkout would wipe, stashes or forces', () async {
    final repo = await makeRepo();
    await git(repo, ['checkout', '-q', '-b', 'other']);
    await git(repo, ['checkout', '-q', '-']);
    await File('${repo.path}/a.txt').writeAsString('dirty\n');
    await File('${repo.path}/new.txt').writeAsString('untracked\n');

    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.unstaged.length == 2 && st.branchNames.contains('other'));
    expect([for (final f in st.wipedByCheckout) f.path], ['a.txt']); // untracked files stay

    expect(await st.switchBranch('other'), isNotNull); // git refuses without a decision
    expect(st.status!.branch, isNot('other'));

    expect(await st.switchBranch('other', how: CheckoutHow.stash), isNull);
    await until(() => st.status?.branch == 'other');
    expect(st.wipedByCheckout, isEmpty);
    expect(await git(repo, ['stash', 'list']), contains('before switching to other'));

    await git(repo, ['checkout', '-q', '-']);
    await File('${repo.path}/a.txt').writeAsString('dirty again\n');
    await until(() => st.wipedByCheckout.isNotEmpty);
    expect(await st.switchBranch('other', how: CheckoutHow.force), isNull);
    await until(() => st.status?.branch == 'other' && st.wipedByCheckout.isEmpty);

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

    // Optimistic: the file is on the other side before git answers, and stays there.
    final unstaging = st.moveFile('c.txt', staged: true);
    expect(st.staged.length, 1);
    expect(fileKind(st.unstaged.single, staged: false), 'untracked');
    expect(await unstaging, isNull);
    expect(st.staged.length, 1);

    // A failed stage puts the file back once git has answered.
    final failing = st.act('stage', (b) => b.stage('no/such/file'), optimistic: () => st.status = st.status!.withFiles([]));
    expect(st.unstaged, isEmpty);
    expect(await failing, isNotNull);
    expect(st.unstaged.single.path, 'c.txt');

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

  test('Right goes from the file list to the diff, Left back; up / down move files', () async {
    final repo = await makeRepo();
    final lines = [for (var i = 1; i <= 12; i++) 'line $i'];
    await File('${repo.path}/a.txt').writeAsString('${lines.join('\n')}\n');
    await git(repo, ['commit', '-q', '-am', 'twelve']);
    lines[0] = 'LINE 1';
    lines[11] = 'LINE 12';
    await File('${repo.path}/a.txt').writeAsString('${lines.join('\n')}\n');
    await File('${repo.path}/c.txt').writeAsString('new\n');
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.diff != null && st.unstaged.length == 2);

    expect(st.pane, ChangesPane.unstaged); // nothing is staged yet
    expect(st.selected, 'a.txt');
    st.moveCursor(1); // files pane: the next file
    expect(st.selected, 'c.txt');
    st.moveCursor(-1);
    await until(() => st.diff != null && st.selected == 'a.txt' && st.diff!.hunks.length == 2);

    st.movePane(1); // Right from the file list: the diff
    expect(st.pane, ChangesPane.diff);
    st.moveCursor(1); // diff pane: scrolls (no scroll view in a unit test), the file stays
    expect(st.selected, 'a.txt');
    st.movePane(-1); // Left: back to the list it came from
    expect(st.pane, ChangesPane.unstaged);

    st.dispose();
    s.dispose();
    await nvim.stop();
  });

  test('Tab cycles STAGED, CHANGES, the commit message, the diff, and round; Shift+Tab goes back', () async {
    final repo = await makeRepo();
    await File('${repo.path}/a.txt').writeAsString('one\nTWO\nthree\nfour\nfive\n');
    await File('${repo.path}/c.txt').writeAsString('new\n');
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.diff != null && st.unstaged.length == 2);
    expect(await st.act('stage', (b) => b.stage('c.txt')), isNull);
    await until(() => st.staged.length == 1 && st.unstaged.length == 1);

    st.goTo(ChangesPane.staged);
    expect(st.selected, 'c.txt');
    expect(st.tabFrom(fromMessage: false, delta: 1), ChangesPane.unstaged);
    expect(st.selected, 'a.txt'); // entering a list selects its first file
    expect(st.tabFrom(fromMessage: false, delta: 1), isNull); // the commit message
    expect(st.tabFrom(fromMessage: true, delta: 1), ChangesPane.diff);
    expect(st.tabFrom(fromMessage: false, delta: 1), ChangesPane.staged); // round again
    expect(st.tabFrom(fromMessage: false, delta: -1), ChangesPane.diff);
    expect(st.tabFrom(fromMessage: false, delta: -1), isNull);
    expect(st.tabFrom(fromMessage: true, delta: -1), ChangesPane.unstaged);

    st.dispose();
    s.dispose();
    await nvim.stop();
  });

  test('Up / Down walk the files as the tree lists them: top-level files, then folders', () async {
    final repo = await makeRepo();
    await Directory('${repo.path}/sub').create();
    for (final f in ['z.txt', 'sub/b.txt', 'sub/a.txt', 'm.txt']) {
      await File('${repo.path}/$f').writeAsString('x\n');
    }
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-q', '-m', 'files']);
    for (final f in ['z.txt', 'sub/b.txt', 'sub/a.txt', 'm.txt', 'a.txt']) {
      await File('${repo.path}/$f').writeAsString('changed\n');
    }
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.unstaged.length >= 5 && st.diff != null);

    // git lists a.txt, m.txt, sub/a.txt, sub/b.txt, z.txt; the tree shows z.txt before sub/.
    final shown = [for (final f in st.unstaged) f.path];
    expect(shown, ['a.txt', 'm.txt', 'z.txt', 'sub/a.txt', 'sub/b.txt']);
    st.goTo(ChangesPane.unstaged);
    final walked = <String>[st.selected!];
    for (var i = 0; i < 4; i++) {
      st.moveCursor(1);
      walked.add(st.selected!);
    }
    expect(walked, shown);

    st.dispose();
    s.dispose();
    await nvim.stop();
  });

  test('Down past the last staged file goes to CHANGES, past the last changed file to the message; Up goes back', () async {
    final repo = await makeRepo();
    await File('${repo.path}/a.txt').writeAsString('one\nTWO\nthree\nfour\nfive\n');
    await File('${repo.path}/c.txt').writeAsString('new\n');
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.diff != null && st.unstaged.length == 2);
    expect(await st.act('stage', (b) => b.stage('c.txt')), isNull);
    await until(() => st.staged.length == 1 && st.unstaged.length == 1);

    st.goTo(ChangesPane.staged);
    expect(st.moveCursor(1), isFalse); // the only staged file: on to CHANGES
    expect(st.pane, ChangesPane.unstaged);
    expect(st.selected, 'a.txt');
    expect(st.moveCursor(-1), isFalse); // back up to STAGED, on its last file
    expect(st.pane, ChangesPane.staged);
    expect(st.selected, 'c.txt');
    st.goTo(ChangesPane.unstaged);
    expect(st.moveCursor(1), isTrue); // below the last changed file: the commit message
    expect(st.pane, ChangesPane.unstaged);

    st.dispose();
    s.dispose();
    await nvim.stop();
  });

  test('Shift+[ and Shift+] move three files in the list and stay in it', () async {
    final repo = await makeRepo();
    final names = [for (var i = 1; i <= 7; i++) 'f$i.txt'];
    for (final n in names) {
      await File('${repo.path}/$n').writeAsString('x\n');
    }
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-q', '-m', 'files']);
    for (final n in names) {
      await File('${repo.path}/$n').writeAsString('changed\n');
    }
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.unstaged.length == 7 && st.diff != null);

    st.goTo(ChangesPane.unstaged);
    final order = [for (final f in st.unstaged) f.path];
    st.select(order.first, staged: false);
    st.jump(1);
    expect(st.selected, order[3]);
    st.jump(1);
    expect(st.selected, order[6]);
    st.jump(1); // the end of the list: stays, and does not hop to another pane
    expect(st.selected, order[6]);
    expect(st.pane, ChangesPane.unstaged);
    st.jump(-1);
    expect(st.selected, order[3]);

    st.dispose();
    s.dispose();
    await nvim.stop();
  });
}
