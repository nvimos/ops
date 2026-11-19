import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/files.dart';
import 'package:nvimos_poc/local/paths.dart';

import 'support/temp_dirs.dart';

Future<Directory> makeTemp() async => keepForCleanup(await Directory.systemTemp.createTemp('nvimos_files_'));

Future<void> write(String path, String text) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(text);
}

String at(Directory dir, String relative) => '${dir.path}/$relative'.replaceAll(r'\', '/');

void main() {
  tearDownAll(removeTempDirs);

  test('without .nvimos the planning folder is the repo root', () async {
    final repo = await makeTemp();
    final t = await LocalFiles(repo.path).tracking();

    expect(t.root, canonicalPath(repo.path));
    expect(t.repoRoot, canonicalPath(repo.path));
    expect(t.project, isNull);
    expect(t.file, isNull);
    expect(t.missing, isNull);
  });

  test('a .nvimos tracking line names the folder, resolved from the repo root', () async {
    final repo = await makeTemp();
    await Directory(at(repo, 'plan')).create();
    await write(at(repo, '.nvimos'), '# where the planning lives\ntracking = plan\nproject = frontend\n');

    final t = await LocalFiles(repo.path).tracking();

    expect(t.root, canonicalPath(at(repo, 'plan')));
    expect(t.repoRoot, canonicalPath(repo.path));
    expect(t.project, 'frontend');
    expect(t.file, canonicalPath(at(repo, '.nvimos')));
    expect(t.missing, isNull);
  });

  test('a tracking folder that is missing falls back to the repo root', () async {
    final repo = await makeTemp();
    await write(at(repo, '.nvimos'), 'tracking = gone\nproject = frontend\n');

    final t = await LocalFiles(repo.path).tracking();

    expect(t.root, canonicalPath(repo.path));
    expect(t.missing, canonicalPath(at(repo, 'gone')));
    expect(t.project, 'frontend');
  });

  test('a relative tracking path may leave the repo folder', () async {
    final parent = await makeTemp();
    await Directory(at(parent, 'plan')).create();
    final repo = Directory(at(parent, 'outer/code'));
    await repo.create(recursive: true);
    await write(at(repo, '.nvimos'), 'tracking = ../../plan\n');

    final t = await LocalFiles(repo.path).tracking();

    expect(t.root, canonicalPath(at(parent, 'plan')));
    expect(t.repoRoot, canonicalPath(repo.path));
  });

  test('listFiles walks nested dirs, sorted by path, relative to the planning folder', () async {
    final repo = await makeTemp();
    await Directory(at(repo, 'plan')).create();
    await write(at(repo, '.nvimos'), 'tracking = plan\n');
    await write(at(repo, 'plan/README.md'), 'x');
    await write(at(repo, 'plan/backlog/tasks/task-1.md'), 'hi');
    await write(at(repo, 'plan/openspec/changes/ui/proposal.md'), '# ui\n');

    final files = LocalFiles(repo.path);
    final nested = await files.listFiles(['backlog', 'openspec']);

    expect(nested.map((f) => f.path), ['backlog/tasks/task-1.md', 'openspec/changes/ui/proposal.md']);
    expect(nested.first.size, 2);
    expect(nested.first.mtime.isAfter(DateTime(2000)), isTrue);

    final all = await files.listFiles(['']);
    expect(all.map((f) => f.path), ['README.md', 'backlog/tasks/task-1.md', 'openspec/changes/ui/proposal.md']);
  });

  test('listFiles skips a missing dir', () async {
    final repo = await makeTemp();
    await Directory(at(repo, 'plan')).create();
    await write(at(repo, '.nvimos'), 'tracking = plan\n');
    await write(at(repo, 'plan/README.md'), 'x');

    final files = LocalFiles(repo.path);
    expect(await files.listFiles(['nope']), isEmpty);
    expect(await files.listFiles(['nope', '']), hasLength(1));
  });

  test('readFiles answers existing files and empty lines for a missing one', () async {
    final repo = await makeTemp();
    await Directory(at(repo, 'plan')).create();
    await write(at(repo, '.nvimos'), 'tracking = plan\n');
    await write(at(repo, 'plan/backlog/tasks/task-1.md'), 'hi');
    await write(at(repo, 'plan/multi.md'), 'a\nb\n');
    await write(at(repo, 'plan/empty.md'), '');

    final read = await LocalFiles(repo.path).readFiles(['backlog/tasks/task-1.md', 'multi.md', 'empty.md', 'nope.md']);

    expect(read.map((f) => f.path), ['backlog/tasks/task-1.md', 'multi.md', 'empty.md', 'nope.md']);
    expect(read.map((f) => f.exists), [true, true, true, false]);
    expect(read[0].lines, ['hi']);
    expect(read[1].lines, ['a', 'b']);
    expect(read[2].lines, isEmpty);
    expect(read[3].lines, isEmpty);
  });
}
