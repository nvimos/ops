import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/backend.dart';
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
}
