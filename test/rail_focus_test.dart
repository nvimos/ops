import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/pr.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/key_sequence.dart';
import 'package:nvimos_poc/ui/shell.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  test('count sequences: 2gi is a command of its own, gi another, i a third', () async {
    final log = <String>[];
    final k = KeySequence({
      'i': () => log.add('i'),
      'gi': () => log.add('gi'),
      '2gi': () => log.add('2gi'),
    }, timeout: const Duration(milliseconds: 20));
    k.press('i');
    k.press('g');
    k.press('i');
    k.press('2');
    k.press('g');
    k.press('i');
    k.press('2');
    k.press('x'); // not a command: dropped
    k.press('i');
    expect(log, ['i', 'gi', '2gi', 'i']);
    k.dispose();
  });

  testWidgets('Tab reaches the mode rail; its cursor starts on the mode; Down, Enter go to another mode', (t) async {
    final s = Session(port: 1); // never connected: no sockets on the fake clock
    await t.pumpWidget(SessionScope(session: s, child: MaterialApp(theme: buildTheme(), home: const Shell())));
    await t.pump();
    expect(find.text('Connect to Neovim'), findsOneWidget);
    expect(focused(), 'shell');

    await t.sendKeyEvent(LogicalKeyboardKey.tab); // the connect screen has no Tab of its own: the rail
    await t.pump();
    expect(focused(), 'rail');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // up from Pull request: the expand / collapse button
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Directories'), findsOneWidget); // the rail expanded: labels show
    expect(focused(), 'rail'); // pressing the button leaves the cursor there
    for (var i = 0; i < 5; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // button -> Pull request -> ... -> Help
    }
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(find.text('Keys'), findsOneWidget); // the Help mode
    expect(focused(), isNot('rail')); // and the keyboard went into it

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    s.dispose();
  });

  test('Pull request: Tab leaves the cycle after the diff, Ctrl+Up/Down hop between the lists', () async {
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
    await until(() => !pr.loading && pr.diff != null && pr.selected == 'a.txt');
    final shell = FocusNode();

    expect(pr.leavesCycle(1), isFalse); // files -> commits
    expect(pr.leavesCycle(-1), isFalse); // files -> head picker
    pr.movePane(1); // the diff, the last stop
    expect(pr.pane, PrPane.diff);
    expect(pr.leavesCycle(1), isTrue); // next is the rail
    expect(pr.leavesCycle(-1), isFalse);

    pr.movePane(-1); // back to the files
    expect(pr.vertical(1, shell), shell); // Ctrl+Down: COMMITS
    expect(pr.pane, PrPane.commits);
    expect(pr.vertical(1, shell), shell); // nothing below the commits: stays
    expect(pr.pane, PrPane.commits);
    expect(pr.vertical(-1, shell), shell); // Ctrl+Up: FILES CHANGED
    expect(pr.pane, PrPane.files);
    expect(pr.vertical(-1, shell), pr.headFocus); // above the files: the head picker

    pr.dispose();
    s.dispose();
    shell.dispose();
    await nvim.stop();
  });

  test('Changes: Tab leaves the cycle at both ends, Ctrl+Up/Down hop STAGED, CHANGES, message', () async {
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

    st.goTo(ChangesPane.diff);
    expect(st.tabLeaves(fromMessage: false, delta: 1), isTrue); // after the diff: the rail
    expect(st.tabLeaves(fromMessage: false, delta: -1), isFalse);
    st.goTo(ChangesPane.staged);
    expect(st.tabLeaves(fromMessage: false, delta: -1), isFalse); // before STAGED: the branch switcher
    st.goTo(ChangesPane.branch);
    expect(st.tabLeaves(fromMessage: false, delta: -1), isTrue); // before the switcher: the rail
    expect(st.tabLeaves(fromMessage: false, delta: 1), isFalse);
    expect(st.vertical(dir: -1, fromMessage: false), isFalse); // nothing above the switcher: stays
    expect(st.pane, ChangesPane.branch);
    expect(st.vertical(dir: 1, fromMessage: false), isFalse); // switcher -> STAGED
    expect(st.pane, ChangesPane.staged);
    expect(st.vertical(dir: -1, fromMessage: false), isFalse); // STAGED -> switcher
    expect(st.pane, ChangesPane.branch);
    expect(st.moveCursor(1), isFalse); // Down: the first list
    expect(st.pane, ChangesPane.staged);
    expect(st.moveCursor(-1), isFalse); // Up past the first file: the switcher
    expect(st.pane, ChangesPane.branch);
    st.leaveBranch();
    expect(st.pane, ChangesPane.staged);
    st.goTo(ChangesPane.staged);

    expect(st.vertical(dir: 1, fromMessage: false), isFalse); // STAGED -> CHANGES
    expect(st.pane, ChangesPane.unstaged);
    expect(st.vertical(dir: 1, fromMessage: false), isTrue); // CHANGES -> the commit message
    expect(st.vertical(dir: 1, fromMessage: true), isTrue); // nothing below it: stays
    expect(st.vertical(dir: -1, fromMessage: true), isFalse); // message -> CHANGES
    expect(st.pane, ChangesPane.unstaged);
    st.goTo(ChangesPane.diff);
    expect(st.vertical(dir: 1, fromMessage: false), isFalse); // the diff is alone in its column
    expect(st.pane, ChangesPane.diff);

    st.dispose();
    s.dispose();
    await nvim.stop();
  });
}
