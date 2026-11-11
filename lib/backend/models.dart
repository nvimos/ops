// Typed views of what the backend plugin returns. Constructors take the decoded msgpack maps.

Map<String, Object?> asMap(Object? v) => v is Map ? v.cast<String, Object?>() : const {};
List<Object?> asList(Object? v) => v is List ? v.cast<Object?>() : const [];
String str(Object? v) => v is String ? v : (v == null ? '' : '$v');
int intOr(Object? v, [int d = 0]) => v is int ? v : (v is double ? v.toInt() : d);

class Branch {
  Branch(Map<String, Object?> m)
    : name = str(m['name']),
      sha = str(m['sha']),
      upstream = str(m['upstream']),
      current = m['current'] == true,
      date = DateTime.fromMillisecondsSinceEpoch(intOr(m['date']) * 1000),
      subject = str(m['subject']);
  final String name, sha, upstream, subject;
  final bool current;
  final DateTime date;
}

class Branches {
  Branches(Map<String, Object?> m)
    : current = m['current'] is String ? m['current'] as String : null,
      list = asList(m['branches']).map((e) => Branch(asMap(e))).toList();
  final String? current;
  final List<Branch> list;
}

class Commit {
  Commit(Map<String, Object?> m)
    : sha = str(m['sha']),
      short = str(m['short']),
      author = str(m['author']),
      date = DateTime.fromMillisecondsSinceEpoch(intOr(m['date']) * 1000),
      subject = str(m['subject']);
  final String sha, short, author, subject;
  final DateTime date;
}

enum LineKind { context, add, del }

class DiffLine {
  DiffLine(Map<String, Object?> m)
    : kind = switch (m['kind']) {
        'add' => LineKind.add,
        'del' => LineKind.del,
        _ => LineKind.context,
      },
      text = str(m['text']),
      oldLine = m['old'] is int ? m['old'] as int : null,
      newLine = m['new'] is int ? m['new'] as int : null,
      noEol = m['no_eol'] == true;
  final LineKind kind;
  final String text;
  final int? oldLine, newLine;
  final bool noEol;
}

class Hunk {
  Hunk(Map<String, Object?> m)
    : header = str(m['header']),
      oldStart = intOr(m['old_start']),
      oldCount = intOr(m['old_count']),
      newStart = intOr(m['new_start']),
      newCount = intOr(m['new_count']),
      section = str(m['section']),
      lines = asList(m['lines']).map((e) => DiffLine(asMap(e))).toList();
  final String header, section;
  final int oldStart, oldCount, newStart, newCount;
  final List<DiffLine> lines;

  Map<String, Object?> get ref => {'old_start': oldStart, 'new_start': newStart};

  /// The first changed line's number in the new file (or the old one for pure deletions).
  int get firstChangedLine {
    for (final l in lines) {
      if (l.kind == LineKind.add) return l.newLine ?? newStart;
      if (l.kind == LineKind.del) return l.oldLine ?? oldStart;
    }
    return newStart;
  }
}

class DiffFile {
  DiffFile(Map<String, Object?> m)
    : path = str(m['path']),
      oldPath = str(m['old_path']),
      status = str(m['status']),
      binary = m['binary'] == true,
      additions = intOr(m['additions']),
      deletions = intOr(m['deletions']),
      hunks = asList(m['hunks']).map((e) => Hunk(asMap(e))).toList();
  final String path, oldPath, status;
  final bool binary;
  final int additions, deletions;
  final List<Hunk> hunks;
}

class PrDiff {
  PrDiff(Map<String, Object?> m)
    : base = str(m['base']),
      head = str(m['head']),
      mergeBase = str(m['merge_base']),
      files = asList(m['files']).map((e) => DiffFile(asMap(e))).toList();
  final String base, head, mergeBase;
  final List<DiffFile> files;
}

class StatusFile {
  StatusFile(Map<String, Object?> m)
    : path = str(m['path']),
      orig = m['orig'] is String ? m['orig'] as String : null,
      index = str(m['index']),
      worktree = str(m['worktree']),
      staged = m['staged'] == true,
      unstaged = m['unstaged'] == true,
      untracked = m['untracked'] == true,
      conflicted = m['conflicted'] == true;

  StatusFile._(this.path, this.orig, this.index, this.worktree, this.staged, this.unstaged, this.untracked, this.conflicted);

  final String path, index, worktree;
  final String? orig;
  final bool staged, unstaged, untracked, conflicted;

  /// The same file staged or unstaged as a whole, as git status would show it (a guess the next
  /// status replaces).
  StatusFile moved({required bool toStaged}) {
    if (toStaged) {
      final kind = untracked ? 'A' : (worktree.trim().isEmpty ? index : worktree);
      return StatusFile._(path, orig, kind, ' ', true, false, false, false);
    }
    final added = index == 'A';
    final kind = unstaged ? worktree : (added ? '?' : index);
    return StatusFile._(path, orig, ' ', kind, false, !added, added, false);
  }
}

class Status {
  Status(Map<String, Object?> m)
    : branch = m['branch'] is String ? m['branch'] as String : null,
      files = asList(m['files']).map((e) => StatusFile(asMap(e))).toList();

  Status._(this.branch, this.files);

  Status withFiles(List<StatusFile> files) => Status._(branch, files);

  final String? branch;
  final List<StatusFile> files;
}

/// Neovim's current window, from the windows domain.
class Cursor {
  Cursor(Map<String, Object?> m)
    : win = intOr(m['win']),
      buf = intOr(m['buf']),
      name = str(m['name']),
      row = intOr(asList(m['cursor']).elementAtOrNull(0), 1),
      col = intOr(asList(m['cursor']).elementAtOrNull(1));
  final int win, buf, row, col;
  final String name;
}

class RepoInfo {
  RepoInfo(Map<String, Object?> m)
    : cwd = str(m['cwd']),
      root = m['root'] is String ? m['root'] as String : null,
      head = m['head'] is String ? m['head'] as String : null;
  final String cwd;
  final String? root, head;
}

class FileText {
  FileText(Map<String, Object?> m)
    : path = str(m['path']),
      exists = m['exists'] == true,
      buffer = m['buffer'] == true,
      lines = asList(m['lines']).map(str).toList();
  final String path;
  final bool exists, buffer;
  final List<String> lines;
}

class FileEntry {
  FileEntry(Map<String, Object?> m)
    : path = str(m['path']),
      size = intOr(m['size']),
      mtime = DateTime.fromMillisecondsSinceEpoch(intOr(m['mtime']) * 1000);
  final String path;
  final int size;
  final DateTime mtime;
}

class CliResult {
  CliResult(Map<String, Object?> m) : code = intOr(m['code'], -1), stdout = str(m['stdout']), stderr = str(m['stderr']);
  final int code;
  final String stdout, stderr;
}

/// One edit for files.set_lines: replace [first, last) (zero-based) with [lines].
class LineEdit {
  LineEdit(this.first, this.last, this.lines, {this.expect});
  final int first, last;
  final List<String> lines;
  final List<String>? expect;

  Map<String, Object?> toMap() => {'first': first, 'last': last, 'lines': lines, if (expect != null) 'expect': expect};
}

/// A command started with the backend's jobs.start.
class Job {
  Job(Map<String, Object?> m)
    : id = intOr(m['id']),
      label = str(m['label']),
      running = m['running'] == true,
      code = m['code'] is int ? m['code'] as int : null,
      stdout = str(m['stdout']),
      stderr = str(m['stderr']);
  final int id;
  final String label, stdout, stderr;
  final bool running;
  final int? code;
}
