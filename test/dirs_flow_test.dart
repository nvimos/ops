import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/dirs_view.dart';
import 'package:nvimos_poc/ui/shell.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';
import 'support/temp_dirs.dart';

String slash(String p) => p.replaceAll(r'\', '/');
String norm(String p) => slash(p).toLowerCase();


/// A spot check of the Directories flow in the whole window: Alt+4, type a filter, Enter picks the
/// dir, and the app-wide mode keys still work afterwards. Neovim runs in real time (runAsync).
void main() {
  testWidgets('Directories: filter + Enter picks the dir, then Alt+[ / Alt+] still switch modes', (t) async {
    final (nvim, s, target) = (await t.runAsync(() async {
      final other = await makeRepo();
      final target = Directory('${keepForCleanup(await Directory.systemTemp.createTemp('nvimos_cfg_')).path}/nvim')..createSync();
      File('${target.path}/init.lua').writeAsStringSync('');
      await git(target, ['init', '-q', '-b', 'main']); // a repo with one untracked file
      final nvim = await TestNvim.start(cwd: other);
      final rpc = await nvim.connect();
      await rpc.request('nvim_set_vvar', [
        'oldfiles',
        [slash('${target.path}/init.lua'), slash('${other.path}/a.txt')],
      ]);
      await rpc.close();
      final s = Session(port: nvim.port);
      await s.connect();
      return (nvim, s, target);
    }))!;
    await t.binding.setSurfaceSize(const Size(1400, 900));
    await t.pumpWidget(SessionScope(session: s, child: MaterialApp(theme: buildTheme(), home: const Shell())));
    await t.pump();

    Future<void> alt(LogicalKeyboardKey k) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyEvent(k);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
    }

    int shown() => t.widget<IndexedStack>(find.byType(IndexedStack)).index!;
    Future<void> settle() async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
    }

    await settle();
    await alt(LogicalKeyboardKey.digit4);
    expect(shown(), Mode.directories.index);

    // The filter has the keyboard: type, then Enter (the text field's "done" action).
    await t.enterText(find.byType(TextField), 'nvim');
    await t.pump();

    // Left in the filter moves the text cursor; at the leftmost edge it goes to the rail.
    final field = t.widget<TextField>(find.byType(TextField)).controller!;
    field.selection = const TextSelection.collapsed(offset: 2);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'dirs filter');
    field.selection = const TextSelection.collapsed(offset: 0);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'rail');
    await t.sendKeyEvent(LogicalKeyboardKey.escape); // back into the mode: its filter again
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'dirs filter');
    expect(field.text, 'nvim');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.runAsync(() => until(() => norm(s.repo?.cwd ?? '') == norm(target.path)));

    // A click on the Active Directory again opens the project; one untracked file: Changes.
    await alt(LogicalKeyboardKey.digit4);
    expect(shown(), Mode.directories.index);
    await t.tap(find.byType(DirRow).first);
    for (var i = 0; i < 3; i++) {
      await settle(); // the mode is chosen after asking git (two calls), round by round
    }
    expect(shown(), Mode.changes.index);

    // The shell's keys still work: back to Pull request, then forward.
    await alt(LogicalKeyboardKey.bracketLeft);
    expect(shown(), Mode.pullRequest.index);
    await alt(LogicalKeyboardKey.bracketRight);
    expect(shown(), Mode.changes.index);

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      s.dispose();
      await nvim.stop();
    });
  });
}
