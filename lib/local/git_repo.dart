/// The git surface the app uses.
///
/// `Repo` is the real one; tests supply a fake, which is why the UI can be driven
/// without a repository, a subprocess or a real clock.
library;

import '../backend/models.dart';
import 'status.dart';

export '../backend/models.dart' show IgnoreAppend, IgnoreFileRef, IgnoreSnapshot;

/// A failure worth showing to the user, with git's own words kept.
class GitException implements Exception {
  GitException(this.message, {this.detail});

  final String message;

  /// The command line and working directory, when the caller knows them.
  final String? detail;

  @override
  String toString() => message;
}

/// One line of `git check-ignore -v`: the file, the line, and the pattern that
/// decided it.
class IgnoreMatch {
  const IgnoreMatch({
    required this.source,
    required this.line,
    required this.pattern,
    required this.path,
  });

  final String source;
  final int line;
  final String pattern;
  final String path;

  /// `<source>:<line>:<pattern>\t<path>`
  static IgnoreMatch? parse(String raw) {
    if (raw.isEmpty) return null;
    final tab = raw.indexOf('\t');
    final head = tab < 0 ? raw : raw.substring(0, tab);
    final path = tab < 0 ? '' : raw.substring(tab + 1);
    // `<source>:<line>:<pattern>`, and `<source>` is an absolute path on Windows,
    // so it starts with a drive letter and a colon of its own. Split from the
    // right: the last `:<digits>:` before the pattern is the separator.
    final match = RegExp(r'^(.*):(\d+):(.*)$').firstMatch(head);
    if (match == null) return null;
    final pattern = match[3]!;
    // git answers a nested repository directory with an empty pattern (the line
    // number is the last pattern line it read). An empty pattern is not a rule:
    // nothing is ignored by it, whatever the exit code says.
    if (pattern.trim().isEmpty) return null;
    return IgnoreMatch(
      source: match[1]!,
      line: int.tryParse(match[2]!) ?? 0,
      pattern: pattern,
      path: path,
    );
  }

  /// `git check-ignore -v -n -z` output: four NUL-terminated fields per path,
  /// `<source> <line> <pattern> <path>`. The fields are separated by NUL, so
  /// the drive letter's colon in `<source>` cannot be mistaken for a separator.
  /// A path no rule matches (`-n`) has an empty source and pattern, and an empty
  /// pattern is never a rule (see [parse]); neither is returned.
  static List<IgnoreMatch> parseZ(String raw) {
    final fields = raw.split('\u0000');
    final found = <IgnoreMatch>[];
    for (var i = 0; i + 3 < fields.length; i += 4) {
      final source = fields[i];
      final pattern = fields[i + 2];
      if (source.isEmpty || pattern.trim().isEmpty) continue;
      found.add(IgnoreMatch(
        source: source,
        line: int.tryParse(fields[i + 1]) ?? 0,
        pattern: pattern,
        path: fields[i + 3],
      ));
    }
    return found;
  }
}

/// Everything the app needs from a repository.
abstract class GitRepo {
  /// Absolute path of the working tree root, with forward slashes.
  String get path;

  Future<List<StatusRow>> status();

  /// Stage whole files, or their deletions when they are gone.
  Future<void> track(Iterable<String> paths);

  /// Stop tracking [paths] but leave them on disk: one `git rm --cached` for
  /// the lot (a few, when the argument list is longer than Windows allows).
  /// Returns the command line that ran last, for the console's report; null
  /// when the implementation does not run git.
  Future<String?> untrack(Iterable<String> paths);

  /// The git command line that ran last, for the console's report; null when the
  /// implementation does not run git.
  String? get lastCommand;

  /// True when [path] holds a repository of its own: an embedded repo, a gitlink
  /// or a submodule. The list marks those rows, because their ignore rules live
  /// inside them, not here.
  Future<bool> isNestedRepository(String path);

  /// The gitlink paths of the index (mode 160000): submodules and embedded repos.
  /// One call answers what a stat per row would otherwise have to guess.
  Future<Set<String>> gitlinks();

  /// Commit the index with one summary line.
  Future<void> commit(String summary);

  /// The checked-out branch (`git branch --show-current`), or null when HEAD is
  /// detached. Read-only: the app names the branch, it never switches it.
  Future<String?> currentBranch();


  /// The rule that ignores [path], if any.
  Future<IgnoreMatch?> checkIgnore(String path);

  /// The rule that ignores each of [paths], in one git call. The keys are the
  /// paths as given; a path no rule matches is not in the map.
  Future<Map<String, IgnoreMatch>> checkIgnoreAll(Iterable<String> paths);

  /// Every `.gitignore` in the working tree, repo-relative.
  Future<List<String>> gitignoreFiles();

  /// The tracked `.gitignore` files that still exist on disk, repo-relative, sorted.
  Future<List<String>> trackedGitignoreFiles();

  /// The untracked, not-ignored `.gitignore` files that exist on disk, repo-relative, sorted.
  Future<List<String>> untrackedGitignoreFiles();

  /// `.git/info/exclude` for this repository.
  Future<String> localExcludePath();

  /// Text of a file, or an empty string when it does not exist.
  Future<String> readTextFile(String absolutePath);

  /// Append one rule to an ignore file.
  Future<IgnoreAppend> appendIgnoreLine(String absolutePath, String pattern);

  /// Append [patterns] to one ignore file with one read and one write. The
  /// answer is aligned with [patterns]: a rule already in the file, or earlier
  /// in the same list, is a [IgnoreAppend.duplicate].
  Future<List<IgnoreAppend>> appendIgnoreLines(String absolutePath, List<String> patterns);

  /// Replace line [number] (1-based) of an ignore file with [replacement], or
  /// remove it when that is null. False, and nothing written, when that line is
  /// no longer [expected]: the file changed since it was read.
  Future<bool> replaceIgnoreLine(String absolutePath, int number, String expected, String? replacement);

  /// Insert [text] as line [number] (1-based), keeping line endings and the final newline.
  /// Throws [GitException] for a number outside `1..lineCount+1`.
  Future<void> insertIgnoreLine(String absolutePath, int number, String text);

  /// Create an empty ignore file with the Purrage header, if it is not there.
  Future<void> createIgnoreFile(String absolutePath);
}
