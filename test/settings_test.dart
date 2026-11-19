import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/local/browser.dart';
import 'package:nvimos_poc/local/editors.dart';
import 'package:nvimos_poc/local/external_editor.dart';
import 'package:nvimos_poc/local/system.dart';
import 'package:nvimos_poc/local/terminals.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/state/settings.dart';
import 'package:nvimos_poc/ui/settings_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'support/fake_system.dart';

/// A machine with VS Code and Windows Terminal on PATH and nothing else.
({Session session, Prefs prefs, FakeRunner runner, SettingsState state, Editors editors}) setUpSettings() {
  final prefs = Prefs.memory();
  final runner = FakeRunner();
  final path = {'code': 'C:\\bin\\code.cmd', 'wt.exe': 'C:\\bin\\wt.exe'};
  final session = Session(prefs: prefs);
  final editors = Editors(
    savedCommand: () => prefs.text(Settings.editorKey),
    which: (exe) async => path[exe],
    exists: (_) async => false,
    gitEditor: () async => null,
    nvimQtCandidates: () async => const [],
    runner: runner,
    env: const Env({}),
  );
  final terminals = TerminalLauncher(runner: runner, which: (exe) async => path[exe]);
  final state = SettingsState(session, editors: editors, terminals: terminals);
  return (session: session, prefs: prefs, runner: runner, state: state, editors: editors);
}

void main() {
  test('detection finds the editor and terminal; an unset choice falls back to the detected one', () async {
    final m = setUpSettings();
    addTearDown(m.session.dispose);
    addTearDown(m.state.dispose);
    await m.state.detect();

    expect(m.state.savedEditor, isNull);
    expect(m.state.editorInUse!.id, 'code');
    expect(m.state.terminalInUse!.id, 'wt');
    expect(m.state.scanDepth, RepoBrowser.depthDefault);
  });

  test('the choices are saved, lead the next detection, and survive a restart', () async {
    final m = setUpSettings();
    addTearDown(m.session.dispose);
    addTearDown(m.state.dispose);
    await m.state.detect();

    await m.state.chooseEditor('"C:\\Tools\\mine.exe" --line {line} {file}');
    expect(m.state.editorInUse!.id, 'saved');
    expect(m.prefs.text(Settings.editorKey), '"C:\\Tools\\mine.exe" --line {line} {file}');

    m.state.chooseTerminal('cmd');
    m.state.setFolderInEditor(true);
    int? told;
    final withDepth = SettingsState(m.session, onDepth: (d) => told = d, editors: m.state.session.editors);
    addTearDown(withDepth.dispose);
    withDepth.setScanDepth(8);
    expect(told, 8);
    withDepth.setScanDepth(99);
    expect(withDepth.scanDepth, RepoBrowser.depthMax, reason: 'clamped');

    // a new state over the same saved prefs sees the same choices
    final again = SettingsState(m.session, editors: m.state.session.editors);
    addTearDown(again.dispose);
    expect(again.savedEditor, '"C:\\Tools\\mine.exe" --line {line} {file}');
    expect(again.savedTerminal, 'cmd');
    expect(again.folderInEditor, isTrue);
    expect(again.scanDepth, RepoBrowser.depthMax);

    await m.state.chooseEditor(null);
    expect(m.state.savedEditor, isNull);
    expect(m.state.editorInUse!.id, 'code');
  });

  test('a local session opens a file in the editor at its line; a missing editor is a message', () async {
    final m = setUpSettings();
    addTearDown(m.session.dispose);
    addTearDown(m.state.dispose);
    final editor = ExternalEditor(m.editors, root: 'C:/work/app');
    await m.state.chooseEditor('"C:\\Tools\\mine.exe" --line {line} {file}');

    await editor.open('src/a.dart', 12);
    final call = m.runner.calls.last;
    expect(call.detached, isTrue);
    expect(call.exe, 'C:\\Tools\\mine.exe');
    expect(call.args, ['--line', '12', 'C:/work/app/src/a.dart']);

    await editor.open('C:/elsewhere/b.txt', 3); // an absolute path stays as it is
    expect(m.runner.calls.last.args.last, 'C:/elsewhere/b.txt');

    await expectLater(editor.show('main', 'a.dart', 1), throwsA(isA<EditorException>()));

    final nothing = Editors(
      which: (_) async => null,
      exists: (_) async => false,
      gitEditor: () async => null,
      nvimQtCandidates: () async => const [],
      runner: m.runner,
      env: const Env({}),
    );
    final found = await nothing.detect();
    expect(found.single.id, 'notepad', reason: 'Notepad is the last resort, never a crash');
  });

  testWidgets('the view lists the editor and terminal in use, and the depth stepper changes the depth', (t) async {
    final m = (await t.runAsync(() async => setUpSettings()))!;
    addTearDown(m.session.dispose);
    addTearDown(m.state.dispose);
    await t.runAsync(() => m.state.detect());
    await t.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: SettingsView(state: m.state))));
    await t.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('VS Code'), findsOneWidget);
    expect(find.text('Windows Terminal'), findsOneWidget);
    expect(m.state.scanDepth, RepoBrowser.depthDefault);
    expect(m.state.wheelStep, Settings.wheelStepDefault, reason: 'the wheel moves 5 rows until changed');

    await t.tap(find.byTooltip('One level more'));
    await t.pump();
    expect(m.state.scanDepth, RepoBrowser.depthDefault + 1);
    expect(find.text('${RepoBrowser.depthDefault + 1}'), findsOneWidget);

    // The wheel step field: a number in range is saved; one out of it says so and is not.
    await t.enterText(find.byType(TextField).last, '7');
    await t.pump();
    expect(m.state.wheelStep, 7);
    await t.enterText(find.byType(TextField).last, '1');
    await t.pump();
    expect(m.state.wheelStep, 7, reason: '1 is below the 2 to 1000 range');
    expect(find.text('2 to 1000'), findsOneWidget, reason: 'the field says why it is not taken');
    expect(find.text('range 2 to 1000'), findsOneWidget);

    await t.tap(find.text('The editor'));
    await t.pump();
    expect(m.state.folderInEditor, isTrue);

    // Delete: the trash by default; asking first is off until chosen, as in Purrage.
    expect(m.state.deleteToTrash, isTrue);
    expect(m.state.confirmDelete, isFalse);
    await t.tap(find.text('For good'));
    await t.pump();
    expect(m.state.deleteToTrash, isFalse);
    expect(m.prefs.flag(Settings.deleteToTrashFlag, fallback: true), isFalse);
    await t.tap(find.text('Ask first'));
    await t.pump();
    expect(m.state.confirmDelete, isTrue);
    expect(m.prefs.flag(Settings.confirmDeleteFlag, fallback: false), isTrue);
  });
}
