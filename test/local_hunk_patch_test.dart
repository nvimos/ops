import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/local/diff_parse.dart';

import 'support/nvim.dart';

DiffFile _file(String path, {String? oldPath, String status = 'modified'}) {
  return DiffFile({
    'path': path,
    'old_path': oldPath ?? path,
    'status': status,
    'hunks': [
      {
        'header': '@@ -1 +1,2 @@',
        'old_start': 1,
        'old_count': 1,
        'new_start': 1,
        'new_count': 2,
        'lines': [
          {'kind': 'context', 'text': 'hello', 'old': 1, 'new': 1},
          {'kind': 'add', 'text': 'world', 'new': 2},
        ],
      },
    ],
  });
}

List<String> _lines(String patch) => patch.split(RegExp(r'\r?\n'));

void main() {
  test('a hunk patch for a spaced path is quoted and git apply accepts it', () async {
    final file = _file('notes/Q3 plan.md');
    final patch = hunkPatch(file, file.hunks.single);
    final lines = _lines(patch);
    expect(lines[0], 'diff --git "a/notes/Q3 plan.md" "b/notes/Q3 plan.md"');
    expect(lines[1], '--- "a/notes/Q3 plan.md"');
    expect(lines[2], '+++ "b/notes/Q3 plan.md"');

    final dir = await makeRepo();
    await Directory('${dir.path}/notes').create();
    await File('${dir.path}/notes/Q3 plan.md').writeAsString('hello\n');
    await git(dir, ['add', '--', 'notes/Q3 plan.md']);
    await git(dir, ['commit', '-q', '-m', 'plan']);
    await File('${dir.path}/hunk.patch').writeAsString(patch);
    await git(dir, ['apply', '--whitespace=nowarn', 'hunk.patch']);
    expect(await File('${dir.path}/notes/Q3 plan.md').readAsString(), 'hello\nworld\n');
  });

  test('a hunk patch for a plain path is unquoted', () async {
    final file = _file('lib/cart.dart');
    final patch = hunkPatch(file, file.hunks.single);
    final lines = _lines(patch);
    expect(lines[0], 'diff --git a/lib/cart.dart b/lib/cart.dart');
    expect(lines[1], '--- a/lib/cart.dart');
    expect(lines[2], '+++ b/lib/cart.dart');
    expect(patch.contains('"'), isFalse);

    final dir = await makeRepo();
    await Directory('${dir.path}/lib').create();
    await File('${dir.path}/lib/cart.dart').writeAsString('hello\n');
    await git(dir, ['add', '--', 'lib/cart.dart']);
    await git(dir, ['commit', '-q', '-m', 'cart']);
    await File('${dir.path}/hunk.patch').writeAsString(patch);
    await git(dir, ['apply', '--whitespace=nowarn', 'hunk.patch']);
    expect(await File('${dir.path}/lib/cart.dart').readAsString(), 'hello\nworld\n');
  });

  test('an added spaced path quotes the new side and leaves /dev/null bare', () {
    final file = _file('notes/Q3 plan.md', oldPath: '', status: 'added');
    final lines = _lines(hunkPatch(file, file.hunks.single));
    expect(lines[0], 'diff --git "a/notes/Q3 plan.md" "b/notes/Q3 plan.md"');
    expect(lines[1], '--- /dev/null');
    expect(lines[2], '+++ "b/notes/Q3 plan.md"');
  });

  test('a real git diff of a spaced path keeps the name', () async {
    final dir = await makeRepo();
    await Directory('${dir.path}/notes').create();
    await File('${dir.path}/notes/Q3 plan.md').writeAsString('hello\n');
    await git(dir, ['add', '--', 'notes/Q3 plan.md']);
    await git(dir, ['commit', '-q', '-m', 'plan']);
    await File('${dir.path}/notes/Q3 plan.md').writeAsString('hello\nworld\n');
    final diff = await git(dir, ['diff', '--', 'notes/Q3 plan.md']);
    final f = parseDiff(diff).single;
    expect(f.path, 'notes/Q3 plan.md');
    expect(f.oldPath, 'notes/Q3 plan.md');
    expect(f.hunks, isNotEmpty);
  });
}
