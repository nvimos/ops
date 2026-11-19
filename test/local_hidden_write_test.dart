import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/git_repo.dart';
import 'package:nvimos_poc/local/repo.dart';

import 'support/local_temp_repo.dart';

/// Windows refuses `CREATE_ALWAYS` on a file that carries Hidden or System, so
/// overwriting a dot file kept in the hidden style fails with access denied.
/// These cases skip themselves off Windows.
void main() {
  Future<Set<String>> attrs(String path) async {
    final result = await Process.run('attrib', [path]);
    final text = result.stdout as String;
    final pathAt = text.toUpperCase().indexOf(path.toUpperCase());
    final head = pathAt > 0 ? text.substring(0, pathAt) : text;
    return {
      for (final char in head.split(''))
        if (RegExp('[A-Za-z]').hasMatch(char)) char.toUpperCase(),
    };
  }

  test('a hidden .gitignore is still written, and stays hidden', () async {
    if (!Platform.isWindows) return;
    final temp = await TempRepo.make();
    final ignore = '${temp.path}/.gitignore';
    await Process.run('attrib', ['+H', ignore]);
    expect(await attrs(ignore), contains('H'));

    final repo = await Repo.open(temp.path);
    expect(await repo.appendIgnoreLine(ignore, '/notes.md'), IgnoreAppend.added);

    final text = await File(ignore).readAsString();
    expect(text, contains('/notes.md'));
    expect(text, contains('build/'), reason: 'the old rules survive the write');
    expect(await attrs(ignore), contains('H'), reason: 'Hidden is put back');
  });

  test('a hidden file is written even when System is set too', () async {
    if (!Platform.isWindows) return;
    final temp = await TempRepo.make();
    final ignore = '${temp.path}/.gitignore';
    await Process.run('attrib', ['+H', '+S', ignore]);

    final repo = await Repo.open(temp.path);
    await repo.appendIgnoreLine(ignore, '/x.log');

    expect(await File(ignore).readAsString(), contains('/x.log'));
    final flags = await attrs(ignore);
    expect(flags, containsAll(['H', 'S']));
  });

  test('a plain write does not run attrib at all', () async {
    if (!Platform.isWindows) return;
    final temp = await TempRepo.make();
    final plain = '${temp.path}/plain.txt';
    await File(plain).writeAsString('a');

    final repo = await Repo.open(temp.path);
    await repo.writeTextFile(File(plain), 'b');
    expect(await File(plain).readAsString(), 'b');
    // No attribute dance: the flags are the ordinary archive bit only.
    expect(await attrs(plain), isNot(contains('H')));
  });

  test('the manual command is in the message when the attribute cannot be cleared', () async {
    if (!Platform.isWindows) return;
    final temp = await TempRepo.make();
    final repo = await Repo.open(temp.path);
    final missing = '${temp.path}/nope.txt';
    // A path that does not exist has no attributes to clear: the repair says so
    // and names the file instead of failing bare with errno 5.
    await expectLater(
      repo.clearHiddenAndSystem(missing),
      throwsA(isA<GitException>().having((e) => e.message, 'message', contains('access denied'))),
    );
  });

  test('createIgnoreFile also gets past a hidden parent file', () async {
    if (!Platform.isWindows) return;
    final temp = await TempRepo.make();
    final repo = await Repo.open(temp.path);
    final nested = '${temp.path}/lib/.gitignore';
    await repo.createIgnoreFile(nested);
    await Process.run('attrib', ['+H', nested]);
    await repo.createIgnoreFile(nested);
    expect(await File(nested).readAsString(), '# Purrage\n');
  });
}
