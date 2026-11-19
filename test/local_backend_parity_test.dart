import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/backend.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/local/local_backend.dart';

import 'support/nvim.dart';

void main() {
  test('LocalBackend and NvimBackend agree on branches, status and a file diff', () async {
    final repo = await makeRepo();
    await File('${repo.path}/a.txt').writeAsString('one\nTWO\nthree\nfour\nfive\n');

    final local = await LocalBackend.open(repo.path);
    addTearDown(local.close);
    final nvim = await TestNvim.start(cwd: repo);
    final remote = await NvimBackend.connect('127.0.0.1', nvim.port);
    addTearDown(remote.close);

    final localBranches = await local.branches();
    final remoteBranches = await remote.branches();
    expect(localBranches.current, remoteBranches.current);
    expect(
      localBranches.list.map((b) => b.name).toSet(),
      remoteBranches.list.map((b) => b.name).toSet(),
    );

    final localStatus = await local.status();
    final remoteStatus = await remote.status();
    expect(localStatus.branch, remoteStatus.branch);
    expect(
      localStatus.files.map((f) => f.path).toSet(),
      remoteStatus.files.map((f) => f.path).toSet(),
    );

    final localDiff = await local.diffFile('a.txt', staged: false);
    final remoteDiff = await remote.diffFile('a.txt', staged: false);
    expect(localDiff, isNotNull);
    expect(remoteDiff, isNotNull);
    expect(localDiff!.hunks.length, remoteDiff!.hunks.length);
    expect(localDiff.additions, remoteDiff.additions);
    expect(localDiff.deletions, remoteDiff.deletions);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('LocalBackend and NvimBackend agree on the ignore-file API', () async {
    final repo = await makeRepo();
    await File('${repo.path}/.gitignore').writeAsString('build/\n');
    await git(repo, ['add', '.gitignore']);
    await Directory('${repo.path}/lib').create();
    await File('${repo.path}/lib/.gitignore').writeAsString('/gen/\n');
    await git(repo, ['add', 'lib/.gitignore']);

    final local = await LocalBackend.open(repo.path);
    addTearDown(local.close);
    final nvim = await TestNvim.start(cwd: repo);
    final remote = await NvimBackend.connect('127.0.0.1', nvim.port);
    addTearDown(remote.close);

    const project = IgnoreFileRef.gitignore('.gitignore');
    const nested = IgnoreFileRef.gitignore('lib/.gitignore');
    const exclude = IgnoreFileRef.exclude();

    final localPanes = await local.loadIgnorePanes();
    final remotePanes = await remote.loadIgnorePanes();
    expect(remotePanes.files, localPanes.files);
    expect(localPanes.files, [project, nested]);
    expect(remotePanes.selected, localPanes.selected);
    expect(remotePanes.text, localPanes.text);
    expect((await remote.loadIgnorePanes(selected: nested)).text, '/gen/\n');

    // A write on either side is seen by the other, and the answers match.
    expect(await remote.appendIgnoreLines(project, ['/a.md', '/a.md']), [
      IgnoreAppend.added,
      IgnoreAppend.duplicate,
    ]);
    expect(await local.readIgnoreFile(project), 'build/\n# Purrage\n/a.md\n');
    await local.insertIgnoreLine(project, 2, '/undo');
    expect(await remote.readIgnoreFile(project), 'build/\n/undo\n# Purrage\n/a.md\n');
    expect(await remote.replaceIgnoreLine(project, 2, '/undo', null), isTrue);
    expect(await local.readIgnoreFile(project), 'build/\n# Purrage\n/a.md\n');

    expect(
      await remote.untrackedIgnoreFiles(),
      await local.untrackedIgnoreFiles(),
    );
    await remote.createIgnoreFile(const IgnoreFileRef.gitignore('new/.gitignore'));
    expect(await local.readIgnoreFile(const IgnoreFileRef.gitignore('new/.gitignore')), '# Purrage\n');

    expect(await local.appendIgnoreLines(exclude, ['*.log']), [IgnoreAppend.added]);
    expect(await remote.readIgnoreFile(exclude), contains('*.log'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
