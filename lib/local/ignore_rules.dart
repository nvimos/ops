/// Which rule to write for a path, and which `.gitignore`-like file it goes in.
///
/// Git reads `.gitignore` at every level, so a rule belongs in the narrowest
/// file that covers the path: patterns in a nested file are relative to that
/// file's folder, patterns in the root file are repo-relative.
library;

/// What the rule should cover.
enum IgnoreScope { file, extension, folder }

/// The four places a rule can live.
enum IgnoreTargetKind { folderGitignore, rootGitignore, localExclude, globalIgnore }

/// One writable ignore file, with the repo-relative folder it governs.
class IgnoreTarget {
  const IgnoreTarget({
    required this.kind,
    required this.label,
    required this.path,
    required this.dir,
    this.exists = false,
  });

  final IgnoreTargetKind kind;
  final String label;

  /// Absolute path, forward slashes.
  final String path;

  /// Repo-relative folder the file sits in; empty for the root.
  final String dir;

  final bool exists;

  bool get isCommitted => kind == IgnoreTargetKind.folderGitignore || kind == IgnoreTargetKind.rootGitignore;
}

/// Pure rule building, so the shapes are unit-tested without git or widgets.
class IgnoreRules {
  /// The line that opens the app's own section in an ignore file.
  static const sectionHeader = '# Purrage';

  /// [existing] with [pattern] added to the `# Purrage` section, or null when the
  /// rule is already anywhere in the file.
  ///
  /// The section is the header and the rules right under it. A new rule goes
  /// directly after the section's last rule, with no blank line, even when other
  /// rules follow further down. A file without the section gets the header at
  /// its end, then the rule; an empty file becomes just the section. The file's
  /// line endings and its final newline (or the lack of one) are kept.
  static String? appendToSection(String existing, String pattern) {
    final lines = _Line.split(existing);
    if (lines.any((line) => line.text.trim() == pattern)) return null;
    final eol = existing.contains('\r\n') ? '\r\n' : '\n';
    if (existing.isEmpty) return '$sectionHeader$eol$pattern$eol';

    final header = lines.indexWhere((line) => line.text.trim() == sectionHeader);
    if (header < 0) {
      lines.add(_Line(sectionHeader, eol));
      lines.add(_Line(pattern, eol));
    } else {
      var end = header + 1;
      while (end < lines.length && _isRule(lines[end].text)) {
        end++;
      }
      lines.insert(end, _Line(pattern, eol));
    }
    _keepFinalNewline(lines, existing, eol);
    return _Line.join(lines);
  }

  /// The rule one folder up, like `dirname`: the last path component taken off,
  /// the rest kept as a folder rule (`/build/out/x.log` and `/build/out/` both
  /// give `/build/out/`... of the first, `/build/` of the second). Null when
  /// there is no folder above (`/x.log`, `*.log`, a comment, a negation) or what
  /// is left names nothing (`**/`), which would ignore far too much.
  static String? dirname(String line) {
    final text = line.trim();
    if (!_isRule(text) || text.startsWith('!')) return null;
    final anchored = text.startsWith('/');
    final parts = text.substring(anchored ? 1 : 0).replaceFirst(RegExp(r'/+$'), '').split('/');
    if (parts.length < 2) return null;
    final kept = parts.sublist(0, parts.length - 1).join('/');
    if (kept.replaceAll(RegExp(r'[*?/\[\]]'), '').isEmpty) return null;
    return '${anchored ? '/' : ''}$kept/';
  }

  /// [text] with line [number] (1-based) replaced by [replacement], or removed
  /// when that is null; the line's own ending is kept. Null when that line is
  /// not [expected] any more: the file changed under the caller.
  static String? replaceLine(String text, int number, String expected, String? replacement) {
    final lines = _Line.split(text);
    if (number < 1 || number > lines.length || lines[number - 1].text != expected) return null;
    if (replacement == null) {
      lines.removeAt(number - 1);
    } else {
      lines[number - 1] = _Line(replacement, lines[number - 1].end);
    }
    return _Line.join(lines);
  }

  static bool _isRule(String line) {
    final text = line.trim();
    return text.isNotEmpty && !text.startsWith('#');
  }

  /// Every line but the last ends with a newline; the last one ends as the file
  /// did.
  static void _keepFinalNewline(List<_Line> lines, String existing, String eol) {
    for (var i = 0; i < lines.length - 1; i++) {
      if (lines[i].end.isEmpty) lines[i] = _Line(lines[i].text, eol);
    }
    final last = lines.length - 1;
    final hadNewline = existing.endsWith('\n');
    if (hadNewline && lines[last].end.isEmpty) lines[last] = _Line(lines[last].text, eol);
    if (!hadNewline && lines[last].end.isNotEmpty) lines[last] = _Line(lines[last].text, '');
  }

  /// The rule that ignores [path] when written into the file that governs
  /// [targetDir]. Returns null when the scope cannot produce a rule (an
  /// extension scope on a file without an extension).
  static String? pattern({
    required IgnoreScope scope,
    required String targetDir,
    required String path,
  }) {
    final cleanPath = _noTrailingSlash(path);
    final cleanDir = _noTrailingSlash(targetDir);
    final relative = cleanDir.isEmpty ? cleanPath : _withoutPrefix(cleanPath, cleanDir);

    switch (scope) {
      case IgnoreScope.file:
        return '/${_escapeSegments(relative)}';
      case IgnoreScope.folder:
        final folder = _folderFor(relative, isFolderRow: path.endsWith('/'));
        if (folder == null) return null;
        return '/${_escapeSegments(folder)}/';
      case IgnoreScope.extension:
        final name = relative.contains('/')
            ? relative.substring(relative.lastIndexOf('/') + 1)
            : relative;
        final dot = name.lastIndexOf('.');
        if (dot <= 0 || dot == name.length - 1) return null;
        return '*.${_escapeSegment(name.substring(dot + 1))}';
    }
  }

  /// The targets to offer for [path], narrowest first.
  static List<IgnoreTarget> targets({
    required String repoPath,
    required List<String> gitignoreFiles,
    required String localExclude,
    required String globalIgnore,
    required String path,
  }) {
    final repo = _noTrailingSlash(repoPath.replaceAll(r'\', '/'));
    final folder = _folderOf(path);
    final existing = gitignoreFiles.map(_noTrailingSlash).toSet();
    final targets = <IgnoreTarget>[];

    if (folder.isNotEmpty) {
      final nested = '$repo/$folder/.gitignore';
      targets.add(IgnoreTarget(
        kind: IgnoreTargetKind.folderGitignore,
        label: folder,
        path: nested,
        dir: folder,
        exists: existing.contains('$folder/.gitignore'),
      ));
    }
    targets.add(IgnoreTarget(
      kind: IgnoreTargetKind.rootGitignore,
      label: 'root',
      path: '$repo/.gitignore',
      dir: '',
      exists: existing.contains('.gitignore'),
    ));
    targets.add(IgnoreTarget(
      kind: IgnoreTargetKind.localExclude,
      label: '.git/info/exclude (not committed)',
      path: localExclude,
      dir: '',
      exists: true,
    ));
    targets.add(IgnoreTarget(
      kind: IgnoreTargetKind.globalIgnore,
      label: 'global ignore (all repos)',
      path: globalIgnore,
      dir: '',
      exists: true,
    ));
    return targets;
  }

  /// The folder a *folder* scope should ignore: a folder row is itself, a file
  /// row is its parent. A top-level file has no folder to name.
  static String? _folderFor(String relative, {required bool isFolderRow}) {
    if (isFolderRow) return relative.isEmpty ? null : relative;
    if (!relative.contains('/')) return null;
    final folder = relative.substring(0, relative.lastIndexOf('/'));
    return folder.isEmpty ? null : folder;
  }

  static String _folderOf(String path) {
    final clean = _noTrailingSlash(path);
    final slash = clean.lastIndexOf('/');
    return slash < 0 ? '' : clean.substring(0, slash);
  }

  static String _withoutPrefix(String path, String dir) {
    final prefix = '$dir/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  static String _noTrailingSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  static String _escapeSegments(String path) => path.split('/').map(_escapeSegment).join('/');

  /// A literal name inside a pattern: glob characters and a leading `!`/`#`
  /// lose their meaning, which is what a filename needs.
  static String _escapeSegment(String name) {
    final buffer = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      if (char == '*' || char == '?' || char == '[' || char == ']') {
        buffer.write(r'\');
      } else if (i == 0 && (char == '!' || char == '#')) {
        buffer.write(r'\');
      }
      buffer.write(char);
    }
    var out = buffer.toString();
    // A trailing space must be escaped or git trims it.
    out = out.replaceAllMapped(RegExp(r' +$'), (match) => r'\ ' * match[0]!.length);
    return out;
  }
}

/// One line of a text file and the ending it had: `\r\n`, `\n`, or nothing for
/// a last line without a final newline.
class _Line {
  const _Line(this.text, this.end);

  final String text;
  final String end;

  static List<_Line> split(String text) {
    final lines = <_Line>[];
    var start = 0;
    while (start < text.length) {
      final newline = text.indexOf('\n', start);
      if (newline < 0) {
        lines.add(_Line(text.substring(start), ''));
        break;
      }
      final crlf = newline > start && text[newline - 1] == '\r';
      lines.add(_Line(text.substring(start, crlf ? newline - 1 : newline), crlf ? '\r\n' : '\n'));
      start = newline + 1;
    }
    return lines;
  }

  static String join(List<_Line> lines) => lines.map((line) => '${line.text}${line.end}').join();
}
