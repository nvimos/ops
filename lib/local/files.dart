import 'dart:convert';
import 'dart:io';

import 'package:nvimos_poc/backend/models.dart';

import 'paths.dart';
import 'system.dart';

/// Where a repo's planning lives (tracking.lua), and the files there (files.lua).
///
/// The planning folder is the repo root, or the folder a `.nvimos` file at the
/// repo root names. Several repos may share one planning folder; `project`
/// names this repo there. Paths handed out are relative to the planning folder
/// and use forward slashes, the same form the Lua backend used.
class LocalFiles {
  LocalFiles(this.repoRoot);

  /// Absolute, forward-slash path of the repository root.
  final String repoRoot;

  /// The planning folder: [Tracking.root] is the repo root without a `.nvimos`,
  /// or when the folder its `tracking` line names is missing.
  Future<Tracking> tracking() async {
    final root = canonicalPath(repoRoot);
    final nvimos = pathIn(root, '.nvimos');
    final file = File(nvimos);
    if (!await file.exists()) {
      return Tracking({'root': root, 'repo_root': root});
    }

    final cfg = _parse(await file.readAsLines());
    var planningRoot = root;
    String? missing;
    if (cfg['tracking'] != null) {
      final dir = _resolve(root, cfg['tracking']!);
      if (await Directory(dir).exists()) {
        planningRoot = dir;
      } else {
        missing = dir;
      }
    }

    return Tracking({
      'root': planningRoot,
      'repo_root': root,
      'project': cfg['project'],
      'file': nvimos,
      'missing': ?missing,
    });
  }

  /// Every file under each of [dirs] (relative to the planning folder), sorted
  /// by path. Missing dirs are skipped, and links are not followed.
  Future<List<FileEntry>> listFiles(List<String> dirs) async {
    final root = (await tracking()).root;
    final out = <FileEntry>[];
    for (final dir in dirs) {
      final base = pathIn(root, dir);
      if (!await Directory(base).exists()) continue;
      try {
        await for (final entity in Directory(base).list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          FileStat stat;
          try {
            stat = await entity.stat();
          } on FileSystemException {
            continue;
          }
          out.add(
            FileEntry({
              'path': _relative(root, entity.path),
              'size': stat.size,
              'mtime': stat.modified.millisecondsSinceEpoch ~/ 1000,
            }),
          );
        }
      } on FileSystemException {
        // A directory that cannot be read is as good as missing.
      }
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// Contents of [paths] (relative to the planning folder, or absolute). A
  /// missing file answers `exists: false` and no lines.
  Future<List<FileText>> readFiles(List<String> paths) async {
    final root = (await tracking()).root;
    final out = <FileText>[];
    for (final path in paths) {
      final file = File(_resolve(root, path));
      if (!await file.exists()) {
        out.add(FileText({'path': path, 'exists': false, 'lines': const <String>[]}));
        continue;
      }
      // vim.fn.readfile never rejects bytes, so malformed UTF-8 is replaced
      // rather than thrown.
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      out.add(FileText({'path': path, 'exists': true, 'lines': _lines(text)}));
    }
    return out;
  }

  /// `key = value` lines of a `.nvimos` file; `#` starts a comment line.
  static Map<String, String> _parse(List<String> lines) {
    final out = <String, String>{};
    final pattern = RegExp(r'^\s*([\w_]+)\s*=\s*(.*?)\s*$');
    for (final line in lines) {
      if (line.trimLeft().startsWith('#')) continue;
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      out[match.group(1)!] = match.group(2)!;
    }
    return out;
  }

  /// A `.nvimos` path made absolute: `~`, an absolute path, or one relative to
  /// [root].
  String _resolve(String root, String value) {
    var path = value;
    if (path == '~' || path.startsWith('~/') || path.startsWith(r'~\')) {
      final home = Env.system().home;
      if (home != null) path = '$home${path.substring(1)}';
    }
    if (hostPaths.isAbsolute(path)) return canonicalPath(path);
    return canonicalPath(hostPaths.join(canonicalPath(root), path));
  }

  /// [full] relative to [root], with forward slashes.
  static String _relative(String root, String full) {
    final rel = hostPaths.relative(hostPaths.normalize(full), from: hostPaths.normalize(root));
    return Platform.isWindows ? rel.replaceAll(r'\', '/') : rel;
  }

  /// Text split the way `vim.fn.readfile` does: no trailing empty line for a
  /// final newline, and no carriage return left from CRLF.
  static List<String> _lines(String text) {
    if (text.isEmpty) return const <String>[];
    final lines = text.split('\n');
    if (lines.last.isEmpty) lines.removeLast();
    return [for (final line in lines) line.endsWith('\r') ? line.substring(0, line.length - 1) : line];
  }
}
