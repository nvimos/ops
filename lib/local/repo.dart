import 'dart:convert';
import 'dart:io';

import 'package:git/git.dart';

import 'git_repo.dart';
import 'hidden_write.dart';
import 'ignore_rules.dart';
import 'paths.dart';
import 'status.dart';
import 'system.dart';

/// The one door to git. Everything shelling out happens here.
///
/// `GitDir` (the `git` package) owns repository discovery and the process
/// plumbing. Status is the exception: its `-z` output is raw bytes and the
/// package decodes with the system encoding, which mangles non-ASCII paths, so
/// this class decodes it as UTF-8 itself. That is the only place the app starts
/// a git process without the package.
class Repo implements GitRepo {
  Repo._(this.dir, {required this.runner, required this.env})
      : hidden = HiddenWrite(runner: runner, isWindows: env.isWindows);

  final GitDir dir;

  /// Status and `attrib` go through this; the rest of git through [dir].
  final ProcessRunner runner;

  /// The environment `open()` read: its `isWindows` drives the Hidden/System repair of dot files.
  final Env env;

  /// The Hidden/System repair for dot files.
  final HiddenWrite hidden;

  /// Absolute path of the working tree root, with forward slashes.
  @override
  String get path => dir.path;

  /// Open the repository at [path].
  ///
  /// The catch is deliberately `Object`, not `Exception`: `GitDir.fromExisting`
  /// throws an `ArgumentError` for a directory it does not accept, and an `Error`
  /// would otherwise escape past every `on Exception` guard and land in the zone
  /// handler as an uncaught exception.
  static Future<Repo> open(
    String path, {
    ProcessRunner runner = const SystemProcessRunner(),
    Env? env,
  }) async {
    try {
      final dir = await GitDir.fromExisting(path, allowSubdirectory: true);
      return Repo._(dir, runner: runner, env: env ?? Env.system());
    } on ProcessException catch (error) {
      throw GitException('git could not be started: ${error.message}');
    } catch (error) {
      throw GitException('not a git repository: $path\n$error');
    }
  }

  @override
  String? lastCommand;

  Future<ProcessResult> _git(List<String> args, {bool throwOnError = true}) {
    lastCommand = 'git ${args.join(' ')}';
    return dir.runCommand(args, throwOnError: throwOnError);
  }

  /// True when there is nothing to stage, change or list.
  Future<bool> isClean() async {
    final rows = await status();
    return rows.isEmpty;
  }

  @override
  Future<List<StatusRow>> status() async {
    final result = await runner.run(
      'git',
      const [
        '--no-optional-locks',
        'status',
        '--porcelain=v1',
        '-z',
        '--untracked-files=all',
        '--find-renames',
      ],
      cwd: path,
      encoding: utf8,
    );
    if (!result.ok) {
      throw GitException('git status failed:\n${result.stderr}');
    }
    return parseStatusZ(result.stdout);
  }

  /// Every path git tracks (the index), relative to the root, in git's order (`git ls-files -z`).
  Future<List<String>> trackedFiles() async {
    final result = await runner.run(
      'git',
      const ['--no-optional-locks', 'ls-files', '-z'],
      cwd: path,
      encoding: utf8,
    );
    if (!result.ok) throw GitException('git ls-files failed:\n${result.stderr}');
    return [for (final p in result.stdout.split('\x00')) if (p.isNotEmpty) p];
  }

  /// Stage a whole file, or a deletion when the file is gone.
  @override
  Future<void> track(Iterable<String> paths) async {
    for (final batch in argumentBatches(paths)) {
      await _git(['add', '--', ...batch]);
    }
  }

  /// Stop tracking [paths] but leave them on disk: one `git rm --cached` per
  /// batch of arguments, usually one for the whole selection.
  @override
  Future<String?> untrack(Iterable<String> paths) async {
    String? ran;
    for (final batch in argumentBatches(paths)) {
      try {
        await _git(['rm', '--cached', '--', ...batch]);
        ran = 'git rm --cached -- ${batch.join(' ')}';
      } on Object catch (error) {
        // The `git` package throws ProcessException, our own code throws
        // GitException: match on the text, which is what actually says why.
        final text = '$error'.toLowerCase();
        final needsForce = text.contains('use -f') || text.contains('force removal');
        if (!needsForce) rethrow;
        // A submodule or a nested repository: its staged content matches neither
        // HEAD nor the working tree, so git insists on -f. With --cached that
        // only drops the index entry; the file or folder stays on disk. git
        // refuses the whole batch for one such path, so the batch is retried.
        await _git(['rm', '--cached', '-f', '--', ...batch]);
        ran = 'git rm --cached -f -- ${batch.join(' ')}';
      }
    }
    return ran;
  }

  /// Windows limits a command line to 32,767 characters. Paths are split into
  /// batches whose arguments stay under [limit], leaving room for git's own
  /// arguments and the quotes around a path with spaces.
  static List<List<String>> argumentBatches(Iterable<String> paths, {int limit = 30000}) {
    final batches = <List<String>>[];
    var current = <String>[];
    var length = 0;
    for (final path in paths) {
      final cost = path.length + 3; // a space and two quotes
      if (current.isNotEmpty && length + cost > limit) {
        batches.add(current);
        current = <String>[];
        length = 0;
      }
      current.add(path);
      length += cost;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  /// Commit the index with one summary line.
  ///
  /// The message goes in on stdin (`git commit -F -`), so a summary that starts
  /// with `-` can never be read as an option. `GitDir.runCommand` has no stdin,
  /// so this goes through the [ProcessRunner], like [checkIgnoreAll].
  @override
  Future<void> commit(String summary) async {
    const args = ['commit', '-F', '-'];
    lastCommand = 'git ${args.join(' ')}';
    final result = await runner.run('git', args, cwd: path, stdin: summary, encoding: utf8);
    if (!result.ok) {
      throw GitException(
        'git commit failed (exit ${result.exitCode}):\n${result.stderr}${result.stdout}',
        detail: 'command: git commit -F - (summary on stdin)\ncwd: $path',
      );
    }
  }

  @override
  Future<String?> currentBranch() async {
    final result = await _git(['branch', '--show-current'], throwOnError: false);
    if (result.exitCode != 0) return null;
    final name = (result.stdout as String).trim();
    return name.isEmpty ? null : name;
  }

  /// The rule that ignores [path], if any: `null` when nothing matches.
  ///
  /// The path is passed without a trailing slash on purpose: `git check-ignore`
  /// on a directory written as `dir/` answers with an empty pattern and the last
  /// line it scanned, i.e. claims a match that does not exist. `dir` answers
  /// honestly, which is what the row's path is anyway.
  @override
  Future<IgnoreMatch?> checkIgnore(String path) async {
    final clean = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final result = await _git(
      ['check-ignore', '-v', '--', clean],
      throwOnError: false,
    );
    if (result.exitCode != 0) return null;
    return IgnoreMatch.parse((result.stdout as String).trim());
  }

  /// One `git check-ignore -v -n -z --stdin` for every path: the paths go in on
  /// stdin, so there is no command line limit, and the answer comes back as NUL
  /// records parsed by [IgnoreMatch.parseZ].
  ///
  /// The second git call (after [status]) that goes through the [ProcessRunner]
  /// rather than the `git` package: `GitDir.runCommand` cannot write to stdin.
  /// Trailing slashes are stripped first, for the reason [checkIgnore] gives. A
  /// fatal answer (exit 128, e.g. a path inside a submodule) would hide every
  /// other path's answer, so it falls back to one call per path.
  @override
  Future<Map<String, IgnoreMatch>> checkIgnoreAll(Iterable<String> paths) async {
    final asked = <String, List<String>>{};
    for (final path in paths) {
      final clean = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
      if (clean.isEmpty) continue;
      asked.putIfAbsent(clean, () => []).add(path);
    }
    if (asked.isEmpty) return {};
    const args = ['check-ignore', '-v', '-n', '-z', '--stdin'];
    lastCommand = 'git ${args.join(' ')}  (${asked.length} paths on stdin)';
    final result = await runner.run(
      'git',
      args,
      cwd: path,
      stdin: asked.keys.map((path) => '$path\u0000').join(),
      encoding: utf8,
    );

    final found = <String, IgnoreMatch>{};
    if (result.exitCode > 1) {
      for (final MapEntry(key: clean, value: originals) in asked.entries) {
        final match = await checkIgnore(clean);
        if (match == null) continue;
        for (final original in originals) {
          found[original] = match;
        }
      }
      return found;
    }
    for (final match in IgnoreMatch.parseZ(result.stdout)) {
      for (final original in asked[match.path] ?? const <String>[]) {
        found[original] = match;
      }
    }
    return found;
  }

  /// Paths inside the repository, for the `.gitignore` list.
  @override
  /// Every `.gitignore` in the working tree, repo-relative.
  ///
  /// `ls-files --cached` keeps listing a tracked file after it is deleted from
  /// disk, and `--others` only sees untracked ones: the list is therefore filtered
  /// against the filesystem, or the pane would show a file the user just removed.
  @override
  Future<List<String>> gitignoreFiles() async {
    final result = await _git([
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '--',
      ':(glob)**/.gitignore',
    ]);
    final listed = (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    final found = <String>[];
    for (final path in listed) {
      if (await File(pathIn(this.path, path)).exists()) found.add(path);
    }
    return found;
  }

  /// The `.gitignore` files git lists for [args] that still exist on disk, sorted. A tracked file
  /// stays in `ls-files --cached` after it is deleted from disk, so the list is filtered against the
  /// filesystem.
  Future<List<String>> _existingGitignores(List<String> args) async {
    final result = await _git([
      'ls-files',
      ...args,
      '--',
      ':(glob)**/.gitignore',
    ]);
    final found = <String>[];
    for (final line in (result.stdout as String).split('\n')) {
      final path = line.trim();
      if (path.isEmpty) continue;
      if (await File(pathIn(this.path, path)).exists()) found.add(path);
    }
    found.sort();
    return found;
  }

  /// The tracked `.gitignore` files that exist on disk.
  @override
  Future<List<String>> trackedGitignoreFiles() => _existingGitignores(const ['--cached']);

  /// The untracked, not-ignored `.gitignore` files that exist on disk.
  @override
  Future<List<String>> untrackedGitignoreFiles() =>
      _existingGitignores(const ['--others', '--exclude-standard']);

  /// `.git/info/exclude` for this repository, resolved through git so worktrees
  /// and submodules land on the right file.
  @override
  Future<String> localExcludePath() async {
    final result = await _git(['rev-parse', '--git-path', 'info/exclude']);
    var out = (result.stdout as String).trim();
    if (out.isEmpty) out = '.git/info/exclude';
    final absolute = out.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(out)
        ? out
        : '$path/$out';
    return absolute.replaceAll(r'\', '/');
  }

  /// Text of an ignore file, or an empty string when it does not exist yet.
  @override
  Future<String> readTextFile(String absolutePath) async {
    final file = File(absolutePath);
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  /// Append one rule to an ignore file; see [appendIgnoreLines].
  @override
  Future<IgnoreAppend> appendIgnoreLine(String absolutePath, String pattern) async =>
      (await appendIgnoreLines(absolutePath, [pattern])).single;

  /// Add rules to the file's `# Purrage` section with one read and one write:
  /// each directly after the section's last rule, no blank lines; a file without
  /// the section gets it at its end. Line endings and the final newline are
  /// kept. A rule already anywhere in the file, or earlier in [patterns], is
  /// left alone; nothing new means no write. See [IgnoreRules.appendToSection].
  @override
  Future<List<IgnoreAppend>> appendIgnoreLines(String absolutePath, List<String> patterns) async {
    final file = File(absolutePath);
    final existing = await readTextFile(absolutePath);
    var text = existing;
    final answers = <IgnoreAppend>[];
    for (final pattern in patterns) {
      final next = IgnoreRules.appendToSection(text, pattern);
      answers.add(next == null ? IgnoreAppend.duplicate : IgnoreAppend.added);
      if (next != null) text = next;
    }
    if (text == existing) return answers;
    await file.parent.create(recursive: true);
    await writeTextFile(file, text);
    return answers;
  }

  /// One read, one write; see [IgnoreRules.replaceLine].
  @override
  Future<bool> replaceIgnoreLine(String absolutePath, int number, String expected, String? replacement) async {
    final text = IgnoreRules.replaceLine(await readTextFile(absolutePath), number, expected, replacement);
    if (text == null) return false;
    await writeTextFile(File(absolutePath), text);
    return true;
  }

  /// Insert one line, keeping line endings and the final newline; see [IgnoreRules.insertLine].
  @override
  Future<void> insertIgnoreLine(String absolutePath, int number, String text) async {
    final next = IgnoreRules.insertLine(await readTextFile(absolutePath), number, text);
    if (next == null) throw GitException('nvimos: no line $number in $absolutePath');
    final file = File(absolutePath);
    await file.parent.create(recursive: true);
    await writeTextFile(file, next);
  }

  /// Create an ignore file that is not there yet: just the `# Purrage` section.
  @override
  Future<void> createIgnoreFile(String absolutePath) async {
    final file = File(absolutePath);
    if (await file.exists()) return;
    await file.parent.create(recursive: true);
    await writeTextFile(file, '${IgnoreRules.sectionHeader}\n');
  }

  /// A `.git` of its own, file or folder, makes the path a repository: an
  /// embedded repo, a gitlink or a submodule. One stat per row that can be one.
  @override
  Future<bool> isNestedRepository(String path) async {
    final clean = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (clean.isEmpty) return false;
    final gitDir = hostPaths.join(canonicalPath(path), '.git');
    final kind = await FileSystemEntity.type(gitDir);
    return kind != FileSystemEntityType.notFound;
  }

  /// `git ls-files -s -z`, keeping the mode-160000 entries.
  @override
  Future<Set<String>> gitlinks() async {
    final result = await _git(['ls-files', '-s', '-z'], throwOnError: false);
    if (result.exitCode != 0) return {};
    final out = result.stdout as String;
    final found = <String>{};
    for (final record in out.split('\u0000')) {
      if (!record.startsWith('160000 ')) continue;
      final tab = record.indexOf('\t');
      if (tab >= 0 && tab + 1 < record.length) found.add(record.substring(tab + 1));
    }
    return found;
  }

  /// Write [text] to [file], getting past the Windows Hidden attribute (see
  /// [HiddenWrite]).
  Future<void> writeTextFile(File file, String text) => hidden.write(file, text);

  /// Clear Hidden and System on [path]; returns the call that sets them again.
  Future<Future<void> Function()> clearHiddenAndSystem(String path) =>
      hidden.clearHiddenAndSystem(path);
}
