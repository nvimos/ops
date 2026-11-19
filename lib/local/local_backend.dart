import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../backend/models.dart';
import '../backend/repo_backend.dart';
import 'diff_parse.dart';
import 'files.dart';
import 'git_repo.dart';
import 'jobs.dart';
import 'paths.dart';
import 'repo.dart';
import 'status.dart';
import 'system.dart';

/// The repository without an editor: git, files, jobs and tracking through the
/// local seams. Read-only for now; staging and commits arrive in TASK-163.
class LocalBackend implements RepoBackend {
  LocalBackend._(this.root, this.repo, this.files, this.jobs, this._runner);

  /// Absolute working-tree root, with forward slashes.
  String root;

  Repo repo;
  LocalFiles files;
  LocalJobs jobs;

  final ProcessRunner _runner;
  final _events = StreamController<NvimEvent>.broadcast();
  final _done = Completer<void>();
  int _jobSeq = 0;
  bool _closed = false;

  /// Open the repository at [path].
  ///
  /// A [jobs] instance supplied by the caller keeps its own `onEvent`; only a
  /// jobs instance created here feeds [events].
  static Future<LocalBackend> open(
    String path, {
    ProcessRunner? runner,
    LocalJobs? jobs,
  }) async {
    final processRunner = runner ?? const SystemProcessRunner();
    final repo = await Repo.open(path, runner: processRunner);
    final root = canonicalPath(repo.path);
    LocalBackend? backend;
    final localJobs = jobs ?? LocalJobs(root, onEvent: (job) => backend?._onJob(job));
    backend = LocalBackend._(root, repo, LocalFiles(root), localJobs, processRunner);
    return backend;
  }

  @override
  Stream<NvimEvent> get events => _events.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cancelJobs();
    await _events.close();
    if (!_done.isCompleted) _done.complete();
  }

  void _onJob(Job job) {
    if (_closed) return;
    _events.add(NvimEvent('jobs', job.running ? 'started' : 'finished', ++_jobSeq, {
      'id': job.id,
      'label': job.label,
      'running': job.running,
      'code': job.code,
      'stdout': job.stdout,
      'stderr': job.stderr,
    }));
  }

  void _cancelJobs() {
    for (final job in jobs.list()) {
      if (job.running) jobs.cancel(job.id);
    }
  }

  /// Run git in [root]; throw [GitException] for an exit code outside [ok].
  Future<ProcessOutput> _git(List<String> args, {Set<int> ok = const {0}, String? stdin}) async {
    final result = await _runner.run('git', args, cwd: root, stdin: stdin, encoding: utf8);
    if (!ok.contains(result.exitCode)) {
      throw GitException(
        'git ${args.first} failed (exit ${result.exitCode}):\n${result.stderr}',
        detail: 'command: git ${args.join(' ')}\ncwd: $root',
      );
    }
    return result;
  }

  // Git ---------------------------------------------------------------------------------------

  @override
  Future<Branches> branches() async {
    const sep = '\u001f';
    const end = '\u001e';
    final result = await _git([
      'for-each-ref',
      '--format=%(refname:short)%1f%(objectname)%1f%(upstream:short)%1f%(HEAD)%1f%(committerdate:unix)%1f%(subject)%1e',
      'refs/heads',
    ]);
    final list = <Map<String, Object?>>[];
    String? current;
    for (final record in result.stdout.split(end)) {
      final text = record.trim();
      if (text.isEmpty) continue;
      final fields = text.split(sep);
      if (fields.length < 6) continue;
      final isCurrent = fields[3].trim() == '*';
      if (isCurrent) current = fields[0];
      list.add({
        'name': fields[0],
        'sha': fields[1],
        'upstream': fields[2],
        'current': isCurrent,
        'date': int.tryParse(fields[4].trim()) ?? 0,
        'subject': fields[5].trim(),
      });
    }
    return Branches({
      'current': current ?? await repo.currentBranch(),
      'branches': list,
    });
  }

  @override
  Future<List<Commit>> log(String base, String head) async {
    final range = base.trim().isEmpty ? head : '$base..$head';
    final result = await _git([
      'log',
      '--no-color',
      '--format=%H%x1f%h%x1f%an%x1f%at%x1f%s%x1e',
      range,
      '--',
    ]);
    final commits = <Commit>[];
    for (final record in result.stdout.split('\u001e')) {
      final text = record.trim();
      if (text.isEmpty) continue;
      final fields = text.split('\u001f');
      if (fields.length < 5) continue;
      commits.add(Commit({
        'sha': fields[0],
        'short': fields[1],
        'author': fields[2],
        'date': int.tryParse(fields[3].trim()) ?? 0,
        'subject': fields[4],
      }));
    }
    return commits;
  }

  @override
  Future<PrDiff> diff(String base, String head) async {
    final mergeBase = await _git(['merge-base', base, head]);
    final result = await _git([
      'diff',
      '--no-ext-diff',
      '--no-color',
      '-M',
      '--src-prefix=a/',
      '--dst-prefix=b/',
      '$base...$head',
      '--',
    ]);
    final files = parseDiff(result.stdout);
    return PrDiff({
      'base': base,
      'head': head,
      'merge_base': mergeBase.stdout.trim(),
      'files': [for (final file in files) _fileMap(file)],
    });
  }

  @override
  Future<Status> status() async {
    final rows = await repo.status();
    final branch = await repo.currentBranch();
    return Status({
      'branch': branch,
      'files': [for (final row in rows) _statusMap(row)],
    });
  }

  @override
  Future<DiffFile?> diffFile(String path, {required bool staged}) async {
    const common = [
      '--no-ext-diff',
      '--no-color',
      '-M',
      '--src-prefix=a/',
      '--dst-prefix=b/',
    ];
    if (staged) {
      final result = await _git(['diff', '--cached', ...common, '--', path]);
      return _firstDiff(result.stdout);
    }

    final result = await _git(['diff', ...common, '--', path]);
    if (result.stdout.trim().isNotEmpty) return _firstDiff(result.stdout);

    // An untracked file is invisible to `git diff`; compare it with /dev/null.
    final status = await _git([
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
      '--',
      path,
    ]);
    final untracked = status.stdout
        .split('\u0000')
        .any((record) => record.startsWith('?? '));
    if (!untracked) return null;

    final created = await _git(
      ['diff', '--no-index', '--no-color', '--', '/dev/null', path],
      ok: const {0, 1},
    );
    return _firstDiff(created.stdout);
  }

  DiffFile? _firstDiff(String text) {
    final parsed = parseDiff(text);
    return parsed.isEmpty ? null : parsed.first;
  }

  Map<String, Object?> _statusMap(StatusRow row) {
    final staged = row.section == Section.staged;
    final changed = row.section == Section.changed;
    final untracked = row.section == Section.untracked;
    final conflicted = row.section == Section.conflicts;
    return {
      'path': row.path,
      if (row.origPath != null) 'orig': row.origPath,
      'index': staged || conflicted ? row.code[0] : (untracked ? '?' : ' '),
      'worktree': changed || conflicted ? row.code[1] : (untracked ? '?' : ' '),
      'staged': staged,
      'unstaged': changed || untracked,
      'untracked': untracked,
      'conflicted': conflicted,
    };
  }

  Map<String, Object?> _fileMap(DiffFile file) => {
    'path': file.path,
    'old_path': file.oldPath,
    'status': file.status,
    'binary': file.binary,
    'additions': file.additions,
    'deletions': file.deletions,
    'hunks': [for (final hunk in file.hunks) _hunkMap(hunk)],
  };

  Map<String, Object?> _hunkMap(Hunk hunk) => {
    'header': hunk.header,
    'old_start': hunk.oldStart,
    'old_count': hunk.oldCount,
    'new_start': hunk.newStart,
    'new_count': hunk.newCount,
    'section': hunk.section,
    'lines': [
      for (final line in hunk.lines)
        {
          'kind': switch (line.kind) {
            LineKind.add => 'add',
            LineKind.del => 'del',
            LineKind.context => 'context',
          },
          'text': line.text,
          if (line.oldLine != null) 'old': line.oldLine,
          if (line.newLine != null) 'new': line.newLine,
          'no_eol': line.noEol,
        },
    ],
  };

  Never _todo() => throw UnimplementedError('local actions land in TASK-163');

  @override
  Future<void> stage(String path) => repo.track([path]);

  @override
  Future<void> unstage(String path) async {
    try {
      await _git(['restore', '--staged', '--', path]);
    } on GitException {
      // A repository with no commit yet has no HEAD to restore from.
      await _git(['rm', '--cached', '-q', '--', path]);
    }
  }

  @override
  Future<void> discard(String path) async {
    final rows = await repo.status();
    StatusRow? row;
    for (final r in rows) {
      if (r.path == path) {
        row = r;
        break;
      }
    }
    if (row != null && row.section == Section.untracked) {
      final full = Directory(pathIn(root, path));
      if (await full.exists()) {
        await full.delete(recursive: true);
      } else {
        final file = File(pathIn(root, path));
        if (await file.exists()) await file.delete();
      }
      return;
    }
    await _git(['restore', '--', path]);
  }

  @override
  Future<void> stageHunk(String path, Hunk h) async {
    final file = await diffFile(path, staged: false);
    if (file == null) throw GitException('no unstaged diff for $path');
    if (file.status == 'added') return stage(path);
    await _applyPatch(_hunkPatch(file, h), cached: true);
  }

  @override
  Future<void> unstageHunk(String path, Hunk h) async {
    final file = await diffFile(path, staged: true);
    if (file == null) throw GitException('no staged diff for $path');
    await _applyPatch(_hunkPatch(file, h), cached: true, reverse: true);
  }

  @override
  Future<void> discardHunk(String path, Hunk h) async {
    final file = await diffFile(path, staged: false);
    if (file == null) throw GitException('no unstaged diff for $path');
    if (file.status == 'added') return discard(path);
    await _applyPatch(_hunkPatch(file, h), reverse: true);
  }

  /// One hunk as a patch `git apply` can take, with the file's own headers.
  String _hunkPatch(DiffFile file, Hunk h) {
    final oldPath = file.oldPath.isEmpty ? file.path : file.oldPath;
    final from = file.status == 'added' ? '/dev/null' : 'a/$oldPath';
    final to = file.status == 'deleted' ? '/dev/null' : 'b/${file.path}';
    final buf = StringBuffer()
      ..writeln('diff --git a/$oldPath b/${file.path}')
      ..writeln('--- $from')
      ..writeln('+++ $to')
      ..writeln(h.header);
    for (final line in h.lines) {
      buf.write(switch (line.kind) {
        LineKind.context => ' ',
        LineKind.add => '+',
        LineKind.del => '-',
      });
      buf.writeln(line.text);
      if (line.noEol) buf.writeln('\\ No newline at end of file');
    }
    return buf.toString();
  }

  Future<void> _applyPatch(String patch, {bool cached = false, bool reverse = false}) async {
    await _git([
      'apply',
      if (cached) '--cached',
      if (reverse) '--reverse',
      '--whitespace=nowarn',
      '-',
    ], stdin: patch);
  }

  @override
  Future<void> checkout(String branch, {CheckoutHow? how}) async {
    if (how == CheckoutHow.force) {
      await _git(['checkout', '-q', '-f', branch]);
      return;
    }
    if (how == CheckoutHow.stash) {
      final dirty = (await _git(['status', '--porcelain', '--untracked-files=no'])).stdout.trim().isNotEmpty;
      if (!dirty) {
        await _git(['checkout', '-q', branch]);
        return;
      }
      await _git(['stash', 'push', '-q', '-m', 'nvimos: before checkout']);
      try {
        await _git(['checkout', '-q', branch]);
      } on Object {
        await _git(['stash', 'pop', '-q'], ok: {0, 1});
        rethrow;
      }
      return;
    }
    await _git(['checkout', '-q', branch]);
  }

  @override
  Future<String> merge(String base, String head) async {
    if (await repo.currentBranch() != base) {
      throw GitException('nvimos: $base is not the checked-out branch; merge works only on it');
    }
    try {
      await _git(['merge', '--no-ff', '-m', "Merge branch '$head' into $base", head]);
    } on GitException {
      await _git(['merge', '--abort'], ok: {0, 128});
      throw GitException('nvimos: the merge conflicts; finish it in the conflict view or the Neovim backend');
    }
    return (await _git(['rev-parse', 'HEAD'])).stdout.trim();
  }

  @override
  Future<String> rebase(String base, String head) async {
    if (await repo.currentBranch() != head) {
      throw GitException('nvimos: $head is not the checked-out branch; rebase works only on it');
    }
    final behind = (await _git(['rev-list', '--count', '$head..$base'])).stdout.trim();
    if (behind == '0') return RepoBackend.upToDate;
    try {
      await _git(['rebase', base]);
    } on GitException {
      await _git(['rebase', '--abort'], ok: {0, 128});
      throw GitException('nvimos: the rebase conflicts; finish it in the Neovim backend');
    }
    return (await _git(['rev-parse', 'HEAD'])).stdout.trim();
  }

  @override
  Future<String> commit(String message) async {
    await _git(['commit', '-q', '-F', '-'], stdin: message);
    return (await _git(['rev-parse', 'HEAD'])).stdout.trim();
  }

  @override
  Future<List<String>> mergePreflight(String base, String head) async => _todo();

  @override
  Future<MergeStart> mergeStart(String base, String head) async => _todo();

  @override
  Future<List<String>> mergeUnmerged(String path) async => _todo();

  @override
  Future<List<ConflictHunk>> mergeHunks(String path, String file) async => _todo();

  @override
  Future<void> mergePick(String path, String file, int index, String side) async => _todo();

  @override
  Future<void> mergeAdd(String path, String file) async => _todo();

  @override
  Future<String> mergeFinish(String base, String head, String path) async => _todo();

  @override
  Future<void> mergeAbort(String path) async => _todo();

  // Files (Tasks mode) ------------------------------------------------------------------------

  @override
  Future<List<FileEntry>> listFiles(List<String> dirs) => files.listFiles(dirs);

  @override
  Future<List<FileText>> readFiles(List<String> paths) => files.readFiles(paths);

  @override
  Future<void> setLines(String path, List<LineEdit> edits) async {
    final file = File(await _trackingPath(path));
    if (!await file.exists()) throw GitException('nvimos: no such file $path');
    final text = await file.readAsString();
    final hadFinalNewline = text.endsWith('\n');
    final lines = const LineSplitter().convert(text);
    final sorted = [...edits]..sort((a, b) => b.first.compareTo(a.first));
    for (final edit in sorted) {
      if (edit.expect != null) {
        final now = lines.sublist(edit.first.clamp(0, lines.length), edit.last.clamp(0, lines.length));
        if (!_sameLines(now, edit.expect!)) {
          throw GitException('nvimos: $path changed since it was read; refresh and try again');
        }
      }
      if (edit.first < 0 || edit.last > lines.length || edit.first > edit.last) {
        throw GitException('nvimos: bad edit range for $path');
      }
      lines.replaceRange(edit.first, edit.last, edit.lines);
    }
    final out = lines.join('\n') + (hadFinalNewline ? '\n' : '');
    await file.writeAsString(out);
  }

  @override
  Future<void> create(String path, List<String> lines) async {
    final file = File(await _trackingPath(path));
    if (await file.exists()) throw GitException('nvimos: $path already exists');
    await file.parent.create(recursive: true);
    await file.writeAsString('${lines.join('\n')}\n');
  }

  @override
  Future<void> move(String from, String to) async {
    final src = await _trackingPath(from);
    final dst = await _trackingPath(to);
    if (!await FileSystemEntity.isFile(src) && !await Directory(src).exists()) {
      throw GitException('nvimos: no such file or folder $from');
    }
    if (await FileSystemEntity.isFile(dst) || await Directory(dst).exists()) {
      throw GitException('nvimos: $to already exists');
    }
    await Directory(dst).parent.create(recursive: true);
    if (await FileSystemEntity.isDirectory(src)) {
      await Directory(src).rename(dst);
    } else {
      await File(src).rename(dst);
    }
  }

  Future<String> _trackingPath(String path) async =>
      pathIn((await files.tracking()).root, path);

  static bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Jobs --------------------------------------------------------------------------------------

  /// [stdin] has no local seam yet: [LocalJobs.start] does not take it.
  @override
  Future<int> startJob(String cmd, List<String> args, {String? stdin, String? label}) =>
      jobs.start(cmd, args, stdin: stdin, label: label);

  @override
  Future<void> cancelJob(int id) async => jobs.cancel(id);

  @override
  Future<CliResult> cli(String cmd, List<String> args) => jobs.cli(cmd, args);

  // Directories and tracking ------------------------------------------------------------------

  @override
  Future<StartDirs> dirs() async => StartDirs({
    'source': 'local',
    'dirs': [root],
  });

  @override
  Future<String> cd(String path) async {
    final repo = await Repo.open(path, runner: _runner);
    final root = canonicalPath(repo.path);
    if (root.toLowerCase() == this.root.toLowerCase()) return this.root;

    _cancelJobs();
    this.repo = repo;
    files = LocalFiles(root);
    jobs = jobs.repoRoot.toLowerCase() == root.toLowerCase()
        ? jobs
        : LocalJobs(root, onEvent: _onJob);
    this.root = root;
    return root;
  }

  @override
  Future<Tracking> tracking() => files.tracking();

  @override
  Future<String?> pluginRoot() async => null;
}
