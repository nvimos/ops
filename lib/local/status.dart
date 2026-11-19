/// The `git status --porcelain=v1 -z` model.
///
/// One call feeds everything the app shows: each entry becomes one or two
/// rows, because a file can be staged and changed at the same time.
library;

/// Where a row sits in the list.
enum Section { conflicts, staged, changed, untracked }

/// What happened to the file, from the side that produced the row.
enum RowKind { added, modified, deleted, renamed, copied, typeChanged, untracked, conflicted }

/// One line of the list: a path, the section it belongs to, and the two
/// porcelain columns it came from.
///
/// What the list and the sort read on every frame or comparison ([name],
/// [folder], their lower-case forms, [key]) is computed once per row, the first
/// time it is asked for, never per call.
class StatusRow {
  StatusRow({
    required this.section,
    required this.kind,
    required this.path,
    required this.code,
    this.origPath,
  });

  final Section section;
  final RowKind kind;

  /// Path relative to the repository root, as git prints it (forward slashes).
  final String path;

  /// The previous path of a rename or copy, when git reported one.
  final String? origPath;

  /// The two porcelain columns, for the row's side only (`M `, ` M`, `??`, `UU`).
  final String code;

  bool get isStaged => section == Section.staged;

  bool get isConflict => section == Section.conflicts;

  /// The name shown in the list: the last segment, with a slash for folders.
  late final String name = _name();

  /// The folder shown after the name, or an empty string at the root.
  late final String folder = _folder();

  /// [folder] and [name] lower-cased, for the case-insensitive sort.
  late final String folderLower = folder.toLowerCase();
  late final String nameLower = name.toLowerCase();

  /// [path] lower-cased, for the filter.
  late final String pathLower = path.toLowerCase();

  /// Identity in the selection: the same path can be a staged and a changed row.
  late final String key = '${section.index}\u0000$path';

  /// True for a directory row: git prints those with a trailing slash.
  bool get isDirectory => path.endsWith('/');

  String _name() {
    final trimmed = isDirectory ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    final base = slash < 0 ? trimmed : trimmed.substring(slash + 1);
    return isDirectory ? '$base/' : base;
  }

  String _folder() {
    final trimmed = isDirectory ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? '' : trimmed.substring(0, slash);
  }

  /// The list order: section, then folder, then base name, both
  /// case-insensitive, matching what the eye scans. Compares the cached
  /// lower-case strings; nothing is allocated per comparison.
  static int compare(StatusRow a, StatusRow b) {
    final bySection = a.section.index.compareTo(b.section.index);
    if (bySection != 0) return bySection;
    final byFolder = a.folderLower.compareTo(b.folderLower);
    if (byFolder != 0) return byFolder;
    return a.nameLower.compareTo(b.nameLower);
  }

  @override
  String toString() => '${section.name} ${code.trim()} $path';
}

/// Codes that mean a merge conflict, whatever side they are on.
const _conflictCodes = {'DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'};

/// Parses the NUL-separated output of
/// `git status --porcelain=v1 -z --untracked-files=all --find-renames`.
///
/// Ignored entries (`!!`) are dropped: the app never lists them.
List<StatusRow> parseStatusZ(String raw) {
  final rows = <StatusRow>[];
  if (raw.isEmpty) return rows;
  final tokens = raw.split('\u0000');
  for (var i = 0; i < tokens.length; i++) {
    final record = tokens[i];
    if (record.length < 4) continue; // "XY p" is the shortest real record
    final x = record[0];
    final y = record[1];
    final code = '$x$y';
    final path = record.substring(3);

    String? origPath;
    if (x == 'R' || x == 'C' || y == 'R' || y == 'C') {
      // -z puts the rename source in the next token, after the new path.
      if (i + 1 < tokens.length) {
        origPath = tokens[++i];
      }
    }

    if (code == '!!') continue;

    if (code == '??') {
      rows.add(StatusRow(
        section: Section.untracked,
        kind: RowKind.untracked,
        path: path,
        code: code,
      ));
      continue;
    }

    if (_conflictCodes.contains(code)) {
      rows.add(StatusRow(
        section: Section.conflicts,
        kind: RowKind.conflicted,
        path: path,
        code: code,
        origPath: origPath,
      ));
      continue;
    }

    if (x != ' ' && x != '?') {
      rows.add(StatusRow(
        section: Section.staged,
        kind: _kindFor(x),
        path: path,
        code: code,
        origPath: x == 'R' || x == 'C' ? origPath : null,
      ));
    }
    if (y != ' ' && y != '?') {
      rows.add(StatusRow(
        section: Section.changed,
        kind: _kindFor(y),
        path: path,
        code: code,
        origPath: y == 'R' || y == 'C' ? origPath : null,
      ));
    }
  }
  return rows;
}

RowKind _kindFor(String column) => switch (column) {
      'A' => RowKind.added,
      'D' => RowKind.deleted,
      'R' => RowKind.renamed,
      'C' => RowKind.copied,
      'T' => RowKind.typeChanged,
      _ => RowKind.modified,
    };

/// The rows whose path contains [query], case-insensitive. A plain substring on
/// purpose: predictable, and fast enough for the sizes a working tree reaches.
List<StatusRow> filterRows(List<StatusRow> rows, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return rows;
  return [
    for (final row in rows)
      if (row.pathLower.contains(needle)) row,
  ];
}
