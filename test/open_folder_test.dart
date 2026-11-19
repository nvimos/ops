import 'package:nvimos_poc/local/external_editor.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/local/local_backend.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/connect.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'support/nvim.dart';
import 'support/temp_dirs.dart';

void main() {
  test('a folder opens with the local backend: an external editor, the repository watched, remembered', () async {
    final repo = await makeRepo();
    final s = Session();
    addTearDown(s.dispose);
    addTearDown(s.disconnect); // runs first: the watcher lets go of the folder before it is deleted

    await s.openFolder(repo.path);

    expect(s.conn, Conn.connected);
    expect(s.error, isNull);
    expect(s.kind, BackendKind.local);
    expect(s.backend, isA<LocalBackend>());
    expect(s.editor, isA<ExternalEditor>(), reason: 'a local session opens files in the editor Settings names');
    expect(s.repo!.head, 'main');
    expect((await s.backend!.status()).branch, 'main');
    expect(s.recents.single.kind, BackendKind.local);

    // the watcher is on: an edit from outside raises the git hint without a click
    final before = s.gitChanged.value;
    await File('${repo.path}/a.txt').writeAsString('changed\n');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(s.gitChanged.value, greaterThan(before));
  });

  test('a folder that cannot be opened is an error, not a stuck connection', () async {
    // (a plain temp folder would do, but this machine's home folder is itself a repository)
    final dir = keepForCleanup(await Directory.systemTemp.createTemp('nvimos_plain_'));
    final s = Session();
    addTearDown(s.dispose);
    addTearDown(s.disconnect); // runs first: the watcher lets go of the folder before it is deleted

    await s.openFolder('${dir.path}/missing');

    expect(s.conn, Conn.disconnected);
    expect(s.error, startsWith('cannot open'));
    expect(s.recents, isEmpty);
  });

  test('an address still selects Neovim, and switching backends resets the old one', () async {
    final repo = await makeRepo();
    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    addTearDown(s.dispose);
    addTearDown(s.disconnect); // runs first: the watcher lets go of the folder before it is deleted

    await s.connect();
    expect(s.kind, BackendKind.nvim);
    expect(s.editor, isNotNull);
    final nvimEpoch = s.epoch;
    await s.store.refresh();
    expect(s.store.status, isNotNull);

    await s.openFolder(repo.path);
    expect(s.kind, BackendKind.local);
    expect(s.editor, isA<ExternalEditor>());
    expect(s.epoch, greaterThan(nvimEpoch));
    expect(s.recents.map((r) => r.kind), [BackendKind.local, BackendKind.nvim]);

    await s.openRecent(s.recents.last);
    expect(s.kind, BackendKind.nvim);
    expect(s.editor, isNotNull);
  });

  test('the recent list keeps the newest first, no duplicates, at most twelve', () {
    final p = Prefs.memory();
    for (var i = 0; i < 15; i++) {
      p.addRecent(Recent(BackendKind.local, 'C:/r$i'));
    }
    p.addRecent(const Recent(BackendKind.local, 'C:/r10'));
    expect(p.recents(), hasLength(Prefs.maxRecents));
    expect(p.recents().first.target, 'C:/r10');
    expect(p.recents().where((r) => r.target == 'C:/r10'), hasLength(1));
    p.removeRecent(const Recent(BackendKind.local, 'C:/r10'));
    expect(p.recents().any((r) => r.target == 'C:/r10'), isFalse);
  });

  testWidgets('the Connect screen lists the recent folders and addresses, and forgets one', (t) async {
    final p = Prefs.memory()
      ..addRecent(const Recent(BackendKind.nvim, '127.0.0.1:6666'))
      ..addRecent(const Recent(BackendKind.local, 'C:/work/app'));
    final s = Session(port: 1, prefs: p);
    addTearDown(s.dispose);
    addTearDown(s.disconnect); // runs first: the watcher lets go of the folder before it is deleted
    await t.pumpWidget(SessionScope(session: s, child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: ConnectScreen()))));
    await t.pump();

    expect(find.text('C:/work/app'), findsOneWidget);
    expect(find.text('127.0.0.1:6666'), findsOneWidget);
    expect(find.text('folder'), findsOneWidget);
    expect(find.text('Neovim'), findsOneWidget);
    expect(find.text('Open folder'), findsOneWidget);
    expect(find.text('Connect to Neovim'), findsOneWidget);

    await t.tap(find.byIcon(Icons.close).first);
    await t.pump();
    expect(find.text('C:/work/app'), findsNothing);
    expect(p.recents().single.target, '127.0.0.1:6666');
  });
}
