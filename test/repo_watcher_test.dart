import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/repo_backend.dart';
import 'package:nvimos_poc/local/local_backend.dart';
import 'package:nvimos_poc/local/repo_watcher.dart';

import 'support/nvim.dart';
import 'support/temp_dirs.dart';

/// A watcher on [dir] that closes with the test. A short debounce keeps the tests quick.
RepoWatcher watch(Directory dir, {Duration debounce = const Duration(milliseconds: 60)}) {
  final w = RepoWatcher(dir.path, debounce: debounce, maxWait: const Duration(milliseconds: 600));
  addTearDown(w.close);
  return w;
}

Future<Directory> scratch() async => keepForCleanup(await Directory.systemTemp.createTemp('nvimos_watch_'));

void main() {
  test('a file written outside Ops gives one change after the debounce', () async {
    final dir = await scratch();
    final w = watch(dir);
    final seen = <RepoChange>[];
    w.changes.listen(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    for (var i = 0; i < 5; i++) {
      await File('${dir.path}/f$i.txt').writeAsString('x$i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(seen, hasLength(1), reason: 'a burst of writes is one signal');
    expect(seen.single.paths, containsAll(['f0.txt', 'f4.txt']));
    expect(seen.single.refs, isFalse);
  });

  test('objects, lock files and build folders raise nothing; HEAD, refs and index do', () async {
    final dir = await scratch();
    for (final d in ['.git/objects/ab', '.git/refs/heads', 'build', 'node_modules/x']) {
      await Directory('${dir.path}/$d').create(recursive: true);
    }
    final w = watch(dir);
    final seen = <RepoChange>[];
    w.changes.listen(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await File('${dir.path}/.git/objects/ab/cdef').writeAsString('blob');
    await File('${dir.path}/.git/index.lock').writeAsString('');
    await File('${dir.path}/build/out.bin').writeAsString('b');
    await File('${dir.path}/node_modules/x/y.js').writeAsString('j');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seen, isEmpty);

    await File('${dir.path}/.git/refs/heads/main').writeAsString('abc');
    await File('${dir.path}/.git/index').writeAsString('i');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seen, hasLength(1));
    expect(seen.single.refs, isTrue);
    expect(seen.single.index, isTrue);
    expect(seen.single.paths, isEmpty, reason: '.git files are not working-tree paths');
  });

  test('a path the repository ignores raises nothing', () async {
    final dir = await scratch();
    final w = RepoWatcher(
      dir.path,
      debounce: const Duration(milliseconds: 60),
      ignored: (rel) => rel.endsWith('.log'),
    );
    addTearDown(w.close);
    final seen = <RepoChange>[];
    w.changes.listen(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await File('${dir.path}/debug.log').writeAsString('l');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seen, isEmpty);
  });

  test('closing stops it: nothing arrives afterwards', () async {
    final dir = await scratch();
    final w = RepoWatcher(dir.path, debounce: const Duration(milliseconds: 60));
    final seen = <RepoChange>[];
    final done = Completer<void>();
    w.changes.listen(seen.add, onDone: done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await w.close();
    await done.future.timeout(const Duration(seconds: 2));
    await File('${dir.path}/late.txt').writeAsString('x');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(seen, isEmpty);
  });

  test('a local backend turns the change into the git event, once, and stops with close', () async {
    final repo = await makeRepo();
    final backend = await LocalBackend.open(repo.path);
    addTearDown(backend.close);
    backend.watch(watcher: RepoWatcher(repo.path, debounce: const Duration(milliseconds: 60)));
    final seen = <NvimEvent>[];
    backend.events.listen(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await File('${repo.path}/a.txt').writeAsString('changed\n');
    await File('${repo.path}/new.txt').writeAsString('new\n');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(seen.map((e) => e.domain), ['git']);
    expect(seen.single.data['head'], 'main');
    expect(seen.single.data['paths'], containsAll(['a.txt', 'new.txt']));

    final w = backend.watcher!;
    await backend.close();
    expect(backend.watcher, isNull);
    await File('${repo.path}/after.txt').writeAsString('x');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(seen, hasLength(1));
    await w.close(); // already closed by the backend; a second close is harmless
  });

  test('head names the branch, and is null when detached', () async {
    final repo = await makeRepo();
    final w = watch(repo);
    expect(w.head(), 'main');
    await git(repo, ['checkout', '-q', '--detach']);
    expect(w.head(), isNull);
  });
}
