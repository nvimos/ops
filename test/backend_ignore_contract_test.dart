import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/repo_backend.dart';
import 'package:nvimos_poc/local/git_repo.dart';
import 'package:nvimos_poc/local/ignore_rules.dart';
import 'package:nvimos_poc/local/local_backend.dart';

import 'support/local_temp_repo.dart';

/// The ignore-file API both backends answer. The same steps run against [LocalBackend] and against
/// a fake remote backend; the fake never touches this machine's filesystem, and its root does not
/// exist, so a call that leaked a local path would fail instead of passing unnoticed.
void main() {
  test('LocalBackend answers the ignore-file contract', () async {
    final workspace = await LocalIgnoreWorkspace.open();
    addTearDown(workspace.close);
    await expectIgnoreContract(workspace);
  });

  test('a remote backend answers the same contract without local files', () async {
    final workspace = FakeRemoteWorkspace();
    expect(Directory(workspace.root).existsSync(), isFalse);
    await expectIgnoreContract(workspace);
    expect(Directory(workspace.root).existsSync(), isFalse, reason: 'ignore I/O must not touch this machine');
  });
}

Future<void> expectIgnoreContract(IgnoreWorkspace ws) async {
  const project = IgnoreFileRef.gitignore('.gitignore');
  const nested = IgnoreFileRef.gitignore('lib/.gitignore');

  await ws.write('.gitignore', 'build/\n');
  await ws.track('.gitignore');
  await ws.write('lib/.gitignore', '/gen/\n');
  await ws.track('lib/.gitignore');
  await ws.write('web/.gitignore', 'dist/\n');

  // The first load: tracked files only, the project file first, and its text.
  var snapshot = await ws.backend.loadIgnorePanes();
  expect(snapshot.files, [project, nested]);
  expect(snapshot.selected, project);
  expect(snapshot.text, 'build/\n');

  // Asking for a file reads only it, and keeps the selection.
  snapshot = await ws.backend.loadIgnorePanes(selected: nested);
  expect(snapshot.selected, nested);
  expect(snapshot.text, '/gen/\n');

  // A selected file discovery missed is still offered (and the text is read after a write).
  const missed = IgnoreFileRef.gitignore('vendor/.gitignore');
  snapshot = await ws.backend.loadIgnorePanes(selected: missed);
  expect(snapshot.files, [project, nested, missed]);
  expect(snapshot.text, '');

  // The slower second step: untracked nested files, never the project one.
  expect(await ws.backend.untrackedIgnoreFiles(), [const IgnoreFileRef.gitignore('web/.gitignore')]);
  expect(await ws.backend.readIgnoreFile(const IgnoreFileRef.gitignore('web/.gitignore')), 'dist/\n');

  // Append: one read and one write, the # Purrage section, duplicates named.
  expect(await ws.backend.appendIgnoreLines(project, ['/a.md', '*.tmp', '/a.md']), [
    IgnoreAppend.added,
    IgnoreAppend.added,
    IgnoreAppend.duplicate,
  ]);
  expect(
    await ws.backend.readIgnoreFile(project),
    'build/\n# Purrage\n/a.md\n*.tmp\n',
  );

  // Replace is 1-based and refuses when the line is no longer what was read.
  expect(await ws.backend.replaceIgnoreLine(project, 1, 'build/', '/build/'), isTrue);
  expect(await ws.backend.replaceIgnoreLine(project, 1, 'build/', '/other/'), isFalse);
  expect(await ws.backend.readIgnoreFile(project), '/build/\n# Purrage\n/a.md\n*.tmp\n');
  expect(await ws.backend.replaceIgnoreLine(project, 3, '/a.md', null), isTrue);
  expect(await ws.backend.readIgnoreFile(project), '/build/\n# Purrage\n*.tmp\n');

  // Insert for Undo: 1-based, keeps line endings, validates the range.
  await ws.backend.insertIgnoreLine(project, 2, '/a.md');
  expect(await ws.backend.readIgnoreFile(project), '/build/\n/a.md\n# Purrage\n*.tmp\n');
  await expectLater(ws.backend.insertIgnoreLine(project, 99, 'x'), throwsA(anything));

  // Create: the # Purrage header, and a no-op when the file exists.
  const created = IgnoreFileRef.gitignore('new/.gitignore');
  await ws.backend.createIgnoreFile(created);
  expect(await ws.backend.readIgnoreFile(created), '# Purrage\n');
  await ws.backend.createIgnoreFile(created);
  expect(await ws.backend.readIgnoreFile(created), '# Purrage\n');

  // The exclude target is resolved by the backend, never a repo-relative path.
  const exclude = IgnoreFileRef.exclude();
  expect(await ws.backend.appendIgnoreLines(exclude, ['*.log']), [IgnoreAppend.added]);
  expect(await ws.backend.readIgnoreFile(exclude), contains('*.log'));
  await ws.backend.createIgnoreFile(exclude);
  expect(await ws.backend.readIgnoreFile(exclude), contains('*.log'));
}

/// A repository the contract can read and write, plus its backend.
abstract class IgnoreWorkspace {
  RepoBackend get backend;
  Future<void> write(String path, String text);
  Future<void> track(String path);
}

class LocalIgnoreWorkspace implements IgnoreWorkspace {
  LocalIgnoreWorkspace._(this._temp, this.backend);

  final TempRepo _temp;
  @override
  final RepoBackend backend;

  static Future<LocalIgnoreWorkspace> open() async {
    final temp = await TempRepo.make(withGitignore: false);
    final backend = await LocalBackend.open(temp.path);
    return LocalIgnoreWorkspace._(temp, backend);
  }

  Future<void> close() => backend.close();

  @override
  Future<void> write(String path, String text) => _temp.write(path, text);

  @override
  Future<void> track(String path) => _temp.git(['add', '--', path]);
}

/// A backend in another machine's Neovim: repo-relative paths into memory, no filesystem at all.
class FakeRemoteWorkspace implements IgnoreWorkspace {
  FakeRemoteWorkspace() : backend = _FakeRemoteBackend(root: 'C:/nvimos-contract-remote-${DateTime.now().microsecondsSinceEpoch}');

  /// A path on this machine that must never be created.
  String get root => (backend as _FakeRemoteBackend).root;

  @override
  final RepoBackend backend;

  @override
  Future<void> write(String path, String text) async {
    final fake = backend as _FakeRemoteBackend;
    fake.texts[path] = text;
    fake.untracked.add(path);
  }

  @override
  Future<void> track(String path) async {
    final fake = backend as _FakeRemoteBackend;
    fake.tracked.add(path);
    fake.untracked.remove(path);
  }
}

class _FakeRemoteBackend implements RepoBackend {
  _FakeRemoteBackend({required this.root});

  final String root;
  final texts = <String, String>{};
  final tracked = <String>{};
  final untracked = <String>{};
  String excludeText = '';

  @override
  Stream<NvimEvent> get events => const Stream.empty();
  @override
  Future<void> get done => Completer<void>().future;
  @override
  Future<void> close() async {}

  String _read(IgnoreFileRef file) => file.exclude ? excludeText : (texts[file.path] ?? '');

  void _write(IgnoreFileRef file, String text) {
    if (file.exclude) {
      excludeText = text;
    } else {
      texts[file.path] = text;
    }
  }

  @override
  Future<IgnoreSnapshot> loadIgnorePanes({IgnoreFileRef? selected}) async {
    const project = IgnoreFileRef.gitignore('.gitignore');
    final others = <IgnoreFileRef>[
      for (final path in tracked)
        if (path != project.path) IgnoreFileRef.gitignore(path),
    ];
    if (selected != null &&
        !selected.exclude &&
        selected.path != project.path &&
        !others.contains(selected)) {
      others.add(selected);
    }
    others.sort((a, b) => a.path.compareTo(b.path));
    final files = <IgnoreFileRef>[if (texts.containsKey(project.path)) project, ...others];
    if (selected != null && !files.contains(selected)) files.add(selected);
    final chosen = selected ?? files.firstOrNull;
    return IgnoreSnapshot(files: files, selected: chosen, text: chosen == null ? null : _read(chosen));
  }

  @override
  Future<List<IgnoreFileRef>> untrackedIgnoreFiles() async => [
    for (final path in (untracked.difference(tracked).toList()..sort()))
      if (path != '.gitignore') IgnoreFileRef.gitignore(path),
  ];

  @override
  Future<String> readIgnoreFile(IgnoreFileRef file) async => _read(file);

  @override
  Future<List<IgnoreAppend>> appendIgnoreLines(IgnoreFileRef file, List<String> patterns) async {
    var text = _read(file);
    final answers = <IgnoreAppend>[];
    for (final pattern in patterns) {
      final next = IgnoreRules.appendToSection(text, pattern);
      answers.add(next == null ? IgnoreAppend.duplicate : IgnoreAppend.added);
      if (next != null) text = next;
    }
    _write(file, text);
    return answers;
  }

  @override
  Future<bool> replaceIgnoreLine(IgnoreFileRef file, int number, String expected, String? replacement) async {
    final next = IgnoreRules.replaceLine(_read(file), number, expected, replacement);
    if (next == null) return false;
    _write(file, next);
    return true;
  }

  @override
  Future<void> insertIgnoreLine(IgnoreFileRef file, int number, String text) async {
    final next = IgnoreRules.insertLine(_read(file), number, text);
    if (next == null) throw GitException('nvimos: no line $number');
    _write(file, next);
  }

  @override
  Future<void> createIgnoreFile(IgnoreFileRef file) async {
    if (file.exclude ? excludeText.isNotEmpty : texts.containsKey(file.path)) return;
    _write(file, '${IgnoreRules.sectionHeader}\n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName} is not in this contract');
}
