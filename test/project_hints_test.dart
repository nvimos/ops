import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/project_hints.dart';
import 'package:nvimos_poc/state/prefs.dart';

import 'support/temp_dirs.dart';

String norm(String path) => path.replaceAll(r'\', '/');

Future<Directory> repoDir(String name) async {
  final root = keepForCleanup(await Directory.systemTemp.createTemp('nvimos_hints_'));
  final dir = Directory('${root.path}/$name');
  await Directory('${dir.path}/.git').create(recursive: true);
  return dir;
}

void main() {
  test('connected and active come first; a stale hint stays last', () async {
    final a = await repoDir('a');
    final b = await repoDir('b');
    final stale = '${b.parent.path}/gone';
    final prefs = Prefs.memory()
      ..rememberProject(stale)
      ..rememberProject(a.path);

    final hints = ProjectHints(
      prefs: prefs,
      connectedCwd: a.path,
      active: a.path,
      startDirs: () async => [a.path, stale],
    );
    final list = await hints.resolve();

    expect(list.first.path, norm(a.path));
    expect(list.first.source, 'connected');
    expect(list.where((h) => h.path == norm(a.path)), hasLength(1));
    expect(list.last.path, norm(stale));
    expect(list.last.stale, isTrue);
  });

  test('local mode works from the recent list with no Neovim', () async {
    final a = await repoDir('a');
    final prefs = Prefs.memory()..rememberProject(a.path);
    final list = await ProjectHints(prefs: prefs).resolve();
    expect(list.single.path, norm(a.path));
    expect(list.single.stale, isFalse);
    expect(list.single.source, 'recent');
  });

  test('startDirectory: connected, then last folder, then home', () async {
    final prefs = Prefs.memory();
    expect(ProjectHints(prefs: prefs, home: 'C:/home').startDirectory(), 'C:/home');
    prefs.setLastProjectFolder('C:/last');
    expect(ProjectHints(prefs: prefs, home: 'C:/home').startDirectory(), 'C:/last');
    expect(
      ProjectHints(prefs: prefs, home: 'C:/home', connectedCwd: 'C:/nvim').startDirectory(),
      'C:/nvim',
    );
  });
}
