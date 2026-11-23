import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/repo.dart';

import 'temp_dirs.dart';

/// A throwaway repository for one test, deleted when the test ends.
///
/// Everything a test starts or writes goes through here, so a run leaves no
/// `nvimos_repo_*` folder behind.
class TempRepo {
  TempRepo._(this.dir);

  final Directory dir;

  String get path => dir.path.replaceAll(r'\', '/');

  /// The repository at [path], opened through the same seam the app uses.
  Future<Repo> open() => Repo.open(path);

  /// Teardowns run last-registered first, so the delete registered here runs
  /// after a test's own cleanup: the background git work is over before the
  /// folder goes. A folder still locked is left; `temp_dirs` tries once more
  /// when the test file is done.
  static Future<TempRepo> make({bool withGitignore = true}) async {
    final dir = keepForCleanup(await Directory.systemTemp.createTemp('nvimos_repo_'));
    final repo = TempRepo._(dir);
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // locked by a process still holding the folder; leave it to the OS
      }
    });
    await repo.git(['init', '-b', 'main']);
    await repo.git(['config', 'user.email', 'testies@example.com']);
    await repo.git(['config', 'user.name', 'Testies Cohones']);
    await repo.git(['config', 'core.fsmonitor', 'false']);
    // Files come back from git as the test wrote them: the GitHub Windows runner sets
    // core.autocrlf=true system-wide, and a checkout or restore there wrote CRLF.
    await repo.git(['config', 'core.autocrlf', 'false']);
    if (withGitignore) {
      await repo.write('.gitignore', 'build/\n');
      await repo.git(['add', '.gitignore']);
      await repo.git(['commit', '-m', 'create: initial']);
    }
    return repo;
  }

  /// A repository of its own at [relative] inside [outer]; it goes away with
  /// the outer one.
  static Future<TempRepo> nested(TempRepo outer, String relative) async {
    final dir = Directory('${outer.dir.path}/$relative');
    await dir.create(recursive: true);
    final repo = TempRepo._(dir);
    await repo.git(['init', '-q', '-b', 'main']);
    await repo.git(['config', 'user.email', 'testies@example.com']);
    await repo.git(['config', 'user.name', 'Testies Cohones']);
    await repo.git(['config', 'core.fsmonitor', 'false']);
    await repo.git(['config', 'core.autocrlf', 'false']);
    return repo;
  }

  Future<ProcessResult> git(List<String> args) async {
    final result = await Process.run(
      'git',
      ['-c', 'core.fsmonitor=false', ...args],
      workingDirectory: dir.path,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
    }
    return result;
  }

  Future<File> write(String relative, String content) async {
    final file = File('${dir.path}/$relative');
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }
}
