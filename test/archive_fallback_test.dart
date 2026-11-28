import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/backend/repo_backend.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

import 'session_test.dart' show until;
import 'workspace_test.dart' show planRepo;

/// A change with two spec deltas, so the fallback's second spec write can fail.
///
/// The sidebar living spec, when present, is CRLF with no trailing newline: putting the lines back
/// through the backend would not reproduce those bytes.
Future<Directory> twoCapRepo({bool sidebarSpec = true, bool toolbarSpec = true}) async {
  final d = await planRepo();
  Future<void> w(String p, String s) async {
    final f = File('${d.path}/$p');
    await f.parent.create(recursive: true);
    await f.writeAsString(s);
  }

  await w(
    'backlog/tasks/task-1 - first.md',
    '---\nid: TASK-1\ntitle: first\nstatus: In Progress\nlabels: [a]\n---\n\n## Verify\n\n- [ ] try it\n',
  );
  await w(
    'openspec/changes/1-first/proposal.md',
    '# 1. first\n\nStatus: In Progress (backlog TASK-1)\n\n## Why\n\nBecause.\n',
  );
  await w(
    'openspec/changes/1-first/specs/sidebar/spec.md',
    '## ADDED Requirements\n\n### Requirement: Follows the file\nIt SHALL follow.\n',
  );
  await w(
    'openspec/changes/1-first/specs/toolbar/spec.md',
    '## ADDED Requirements\n\n### Requirement: Shows the tools\nIt SHALL show tools.\n',
  );
  await w('index.tsv', 'task\tstatus\tchange\ttitle\tfile\nTASK-1\tIn Progress\t1-first\tfirst\tx.md\n');
  if (sidebarSpec) {
    final f = File('${d.path}/openspec/specs/sidebar/spec.md');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(
      utf8.encode(
        '# sidebar Specification\r\n\r\n## Purpose\r\n\r\nKeep.\r\n\r\n## Requirements\r\n\r\n'
        '### Requirement: Stays put\r\nIt SHALL stay.',
      ),
    );
  }
  if (toolbarSpec) {
    await w(
      'openspec/specs/toolbar/spec.md',
      '# toolbar Specification\n\n## Purpose\n\nTools.\n\n## Requirements\n\n### Requirement: Was here\nIt SHALL remain.\n',
    );
  }
  return d;
}

Future<Session> openSession(Directory repo) async {
  final s = Session();
  addTearDown(s.dispose);
  addTearDown(s.disconnect);
  await s.openFolder(repo.path);
  expect(s.conn, Conn.connected, reason: s.error);
  return s;
}

Future<Workspace> loadWs(Session s) async {
  final ws = Workspace(s);
  addTearDown(ws.dispose);
  await until(() => ws.loaded);
  expect(ws.error, isNull);
  return ws;
}

List<int>? fileBytes(Directory repo, String rel) {
  final f = File('${repo.path}/$rel');
  return f.existsSync() ? f.readAsBytesSync() : null;
}

Map<String, List<int>> tree(Directory repo, String rel) {
  final dir = Directory('${repo.path}/$rel');
  final out = <String, List<int>>{};
  if (!dir.existsSync()) return out;
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File) continue;
    var name = e.path.substring(dir.path.length);
    if (name.startsWith('\\') || name.startsWith('/')) name = name.substring(1);
    out[name.replaceAll('\\', '/')] = e.readAsBytesSync();
  }
  return out;
}

class _Before {
  _Before(this.repo)
    : task = fileBytes(repo, 'backlog/tasks/task-1 - first.md'),
      index = fileBytes(repo, 'index.tsv'),
      sidebar = fileBytes(repo, 'openspec/specs/sidebar/spec.md'),
      toolbar = fileBytes(repo, 'openspec/specs/toolbar/spec.md'),
      change = tree(repo, 'openspec/changes/1-first');

  final Directory repo;
  final List<int>? task, index, sidebar, toolbar;
  final Map<String, List<int>> change;

  void expectUnchanged() {
    expect(fileBytes(repo, 'backlog/tasks/task-1 - first.md'), task);
    expect(fileBytes(repo, 'index.tsv'), index);
    expect(fileBytes(repo, 'openspec/specs/sidebar/spec.md'), sidebar);
    expect(fileBytes(repo, 'openspec/specs/toolbar/spec.md'), toolbar);
    expect(tree(repo, 'openspec/changes/1-first'), change);
    expect(Directory('${repo.path}/openspec/changes/1-first').existsSync(), isTrue);
  }
}

void main() {
  const when = '2026-11-10';

  test('second spec write fails and leaves both specs and the change as they were', () async {
    final repo = await twoCapRepo();
    final before = _Before(repo);
    final s = await openSession(repo);
    final ws = await loadWs(s);
    final gate = _Gate(s.backend!)..failWriteAt = 2;
    s.backend = gate;

    final err = await ws.archive(ws.changes.single, now: DateTime(2026, 11, 10));
    await until(() => !ws.loading);

    expect(err, contains('spec write failed'));
    expect(gate.writes, 2);
    expect(gate.writePaths, ['openspec/specs/sidebar/spec.md']);
    expect(gate.moves, 0);
    expect(ws.task('TASK-1')!.status, 'In Progress');
    before.expectUnchanged();
    expect(Directory('${repo.path}/openspec/changes/archive/$when-1-first').existsSync(), isFalse);
  });

  test('a spec the fallback created is removed when a later write fails', () async {
    final repo = await twoCapRepo(sidebarSpec: false);
    final before = _Before(repo);
    final s = await openSession(repo);
    final ws = await loadWs(s);
    final gate = _Gate(s.backend!)..failWriteAt = 2;
    s.backend = gate;

    final err = await ws.archive(ws.changes.single, now: DateTime(2026, 11, 10));
    await until(() => !ws.loading);

    expect(err, contains('spec write failed'));
    expect(gate.writePaths, ['openspec/specs/sidebar/spec.md']);
    expect(File('${repo.path}/openspec/specs/sidebar/spec.md').existsSync(), isFalse);
    expect(ws.task('TASK-1')!.status, 'In Progress');
    before.expectUnchanged();
  });

  test('a failed move restores the specs and does not mark the change Done', () async {
    final repo = await twoCapRepo();
    final before = _Before(repo);
    final s = await openSession(repo);
    final ws = await loadWs(s);
    final gate = _Gate(s.backend!)..failMove = true;
    s.backend = gate;

    final err = await ws.archive(ws.changes.single, now: DateTime(2026, 11, 10));
    await until(() => !ws.loading);

    expect(err, contains('move failed'));
    expect(gate.moves, 1);
    expect(gate.writePaths, ['openspec/specs/sidebar/spec.md', 'openspec/specs/toolbar/spec.md']);
    expect(ws.task('TASK-1')!.status, 'In Progress');
    before.expectUnchanged();
    expect(Directory('${repo.path}/openspec/changes/archive/$when-1-first').existsSync(), isFalse);
  });

  test('an archive destination that already exists writes nothing', () async {
    final repo = await twoCapRepo();
    final before = _Before(repo);
    final dest = Directory('${repo.path}/openspec/changes/archive/$when-1-first');
    await dest.create(recursive: true);
    final s = await openSession(repo);
    final ws = await loadWs(s);
    final gate = _Gate(s.backend!);
    s.backend = gate;

    final err = await ws.archive(ws.changes.single, now: DateTime(2026, 11, 10));
    await until(() => !ws.loading);

    expect(err, contains('already exists'));
    expect(err, contains('move'));
    expect(gate.writes, 0);
    expect(gate.moves, 0);
    expect(ws.task('TASK-1')!.status, 'In Progress');
    expect(File('${dest.path}/proposal.md').existsSync(), isFalse);
    before.expectUnchanged();
  });

  test('success merges both specs, marks the task Done and moves the folder', () async {
    final repo = await twoCapRepo(toolbarSpec: false);
    final s = await openSession(repo);
    final ws = await loadWs(s);

    expect(await ws.archive(ws.changes.single, now: DateTime(2026, 11, 10)), isNull);
    await until(() => !ws.loading && ws.task('TASK-1')?.status == 'Done');

    final archived = Directory('${repo.path}/openspec/changes/archive/$when-1-first');
    expect(archived.existsSync(), isTrue);
    expect(Directory('${repo.path}/openspec/changes/1-first').existsSync(), isFalse);
    expect(ws.changes.single.archived, isTrue);
    expect(ws.changes.single.id, '1-first');
    expect(File('${repo.path}/backlog/tasks/task-1 - first.md').readAsStringSync(), contains('status: Done'));
    expect(File('${archived.path}/proposal.md').readAsStringSync(), contains('Status: Done (backlog TASK-1)'));
    expect(File('${repo.path}/index.tsv').readAsStringSync(), contains('TASK-1\tDone\t'));
    expect(
      ws.specs.singleWhere((spec) => spec.capability == 'sidebar').requirements.map((r) => r.name),
      containsAll(['Stays put', 'Follows the file']),
    );
    expect(
      ws.specs.singleWhere((spec) => spec.capability == 'toolbar').requirements.single.name,
      'Shows the tools',
    );
  });

  test('openspec on the path is called and the fallback does not write', () async {
    final repo = await twoCapRepo();
    final before = _Before(repo);
    final s = await openSession(repo);
    final ws = await loadWs(s);
    final gate = _Gate(s.backend!)..versionOk = true;
    s.backend = gate;

    final err = await ws.archive(ws.changes.single, now: DateTime(2026, 11, 10));
    await until(() => !ws.loading);

    expect(err, 'not running openspec');
    expect(gate.archiveCalls, 1);
    expect(gate.writes, 0);
    expect(gate.moves, 0);
    expect(ws.task('TASK-1')!.status, 'In Progress');
    before.expectUnchanged();
    expect(Directory('${repo.path}/openspec/changes/archive/$when-1-first').existsSync(), isFalse);
  });
}

/// Forwards to the real backend, and can fail a spec write, the move, or pretend `openspec` is installed.
class _Gate implements RepoBackend {
  _Gate(this.inner);

  final RepoBackend inner;
  var versionOk = false;
  int? failWriteAt;
  var failMove = false;
  var writes = 0;
  var moves = 0;
  var archiveCalls = 0;
  final writePaths = <String>[];

  Future<void> _gateWrite(String path) async {
    writes++;
    if (failWriteAt != null && writes == failWriteAt) throw StateError('spec write failed');
    writePaths.add(path);
  }

  @override
  Stream<NvimEvent> get events => inner.events;
  @override
  Future<void> get done => inner.done;
  @override
  Future<void> close() => inner.close();
  @override
  Future<Branches> branches() => inner.branches();
  @override
  Future<List<Commit>> log(String base, String head) => inner.log(base, head);
  @override
  Future<Set<String>> merged(String base) => inner.merged(base);
  @override
  Future<PrDiff> diff(String base, String head) => inner.diff(base, head);
  @override
  Future<Status> status() => inner.status();
  @override
  Future<DiffFile?> diffFile(String path, {required bool staged}) => inner.diffFile(path, staged: staged);
  @override
  Future<void> stage(String path) => inner.stage(path);
  @override
  Future<void> unstage(String path) => inner.unstage(path);
  @override
  Future<void> discard(String path) => inner.discard(path);
  @override
  Future<void> stageHunk(String path, Hunk h) => inner.stageHunk(path, h);
  @override
  Future<void> unstageHunk(String path, Hunk h) => inner.unstageHunk(path, h);
  @override
  Future<void> discardHunk(String path, Hunk h) => inner.discardHunk(path, h);
  @override
  Future<void> checkout(String branch, {CheckoutHow? how}) => inner.checkout(branch, how: how);
  @override
  Future<String> merge(String base, String head) => inner.merge(base, head);
  @override
  Future<String> rebase(String base, String head) => inner.rebase(base, head);
  @override
  Future<String> commit(String message) => inner.commit(message);
  @override
  Future<List<String>> mergePreflight(String base, String head) => inner.mergePreflight(base, head);
  @override
  Future<MergeStart> mergeStart(String base, String head) => inner.mergeStart(base, head);
  @override
  Future<List<String>> mergeUnmerged(String path) => inner.mergeUnmerged(path);
  @override
  Future<List<ConflictHunk>> mergeHunks(String path, String file) => inner.mergeHunks(path, file);
  @override
  Future<void> mergePick(String path, String file, int index, String side) =>
      inner.mergePick(path, file, index, side);
  @override
  Future<void> mergeAdd(String path, String file) => inner.mergeAdd(path, file);
  @override
  Future<String> mergeFinish(String base, String head, String path) => inner.mergeFinish(base, head, path);
  @override
  Future<void> mergeAbort(String path) => inner.mergeAbort(path);
  @override
  Future<List<FileEntry>> listFiles(List<String> dirs) => inner.listFiles(dirs);
  @override
  Future<List<FileText>> readFiles(List<String> paths) => inner.readFiles(paths);

  @override
  Future<void> setLines(String path, List<LineEdit> edits) async {
    await _gateWrite(path);
    await inner.setLines(path, edits);
  }

  @override
  Future<void> create(String path, List<String> lines) async {
    await _gateWrite(path);
    await inner.create(path, lines);
  }

  @override
  Future<void> move(String from, String to) async {
    moves++;
    if (failMove) throw StateError('move failed');
    await inner.move(from, to);
  }

  @override
  Future<IgnoreSnapshot> loadIgnorePanes({IgnoreFileRef? selected}) => inner.loadIgnorePanes(selected: selected);
  @override
  Future<List<IgnoreFileRef>> untrackedIgnoreFiles() => inner.untrackedIgnoreFiles();
  @override
  Future<String> readIgnoreFile(IgnoreFileRef file) => inner.readIgnoreFile(file);
  @override
  Future<List<IgnoreAppend>> appendIgnoreLines(IgnoreFileRef file, List<String> patterns) =>
      inner.appendIgnoreLines(file, patterns);
  @override
  Future<bool> replaceIgnoreLine(IgnoreFileRef file, int number, String expected, String? replacement) =>
      inner.replaceIgnoreLine(file, number, expected, replacement);
  @override
  Future<void> insertIgnoreLine(IgnoreFileRef file, int number, String text) =>
      inner.insertIgnoreLine(file, number, text);
  @override
  Future<void> createIgnoreFile(IgnoreFileRef file) => inner.createIgnoreFile(file);
  @override
  Future<int> startJob(String cmd, List<String> args, {String? stdin, String? label}) =>
      inner.startJob(cmd, args, stdin: stdin, label: label);
  @override
  Future<void> cancelJob(int id) => inner.cancelJob(id);

  @override
  Future<CliResult> cli(String cmd, List<String> args) async {
    if (versionOk && cmd == 'openspec' && args.length == 1 && args.single == '--version') {
      return CliResult({'code': 0, 'stdout': '1', 'stderr': ''});
    }
    if (versionOk && cmd == 'openspec' && args.isNotEmpty && args.first == 'archive') {
      archiveCalls++;
      return CliResult({'code': 1, 'stdout': '', 'stderr': 'not running openspec'});
    }
    return inner.cli(cmd, args);
  }

  @override
  Future<StartDirs> dirs() => inner.dirs();
  @override
  Future<String> cd(String path) => inner.cd(path);
  @override
  Future<Tracking> tracking() => inner.tracking();
  @override
  Future<String?> pluginRoot() => inner.pluginRoot();
}
