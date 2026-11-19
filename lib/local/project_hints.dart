import 'dart:io';

import '../state/prefs.dart';
import 'paths.dart';

/// One project hint: where it came from and whether it is still a repository.
class ProjectHint {
  const ProjectHint(this.path, this.source, {this.stale = false});

  final String path;

  /// `connected`, `active`, `startdirs` or `recent`.
  final String source;
  final bool stale;

  @override
  String toString() => 'ProjectHint($path, $source, stale: $stale)';
}

/// The likely repositories around the current work: the connected and active
/// folders first, start-dirs/oldfiles from Neovim next, then the local recent
/// list. Only these are hints; the crawler is the source of truth.
class ProjectHints {
  ProjectHints({
    required this.prefs,
    this.connectedCwd,
    this.active,
    this.startDirs,
    this.home,
  });

  final Prefs prefs;
  final String? connectedCwd;
  final String? active;

  /// genja-startdirs/oldfiles from a connected backend; null when local.
  final Future<List<String>> Function()? startDirs;

  /// Overrides the home folder (tests).
  final String? home;

  /// Resolve the hints in display order: connected, active, live hints, stale
  /// hints. Duplicates keep the first source.
  Future<List<ProjectHint>> resolve() async {
    final seen = <String>{};
    final out = <ProjectHint>[];

    void add(String? path, String source) {
      if (path == null || path.trim().isEmpty) return;
      final full = canonicalPath(path);
      if (!seen.add(full.toLowerCase())) return;
      out.add(ProjectHint(full, source));
    }

    add(connectedCwd, 'connected');
    add(active, 'active');
    final hints = await startDirs?.call() ?? const <String>[];
    for (final path in hints) {
      add(path, 'startdirs');
    }
    for (final path in prefs.recentProjects()) {
      add(path, 'recent');
    }

    final checked = <ProjectHint>[];
    for (final hint in out) {
      checked.add(ProjectHint(hint.path, hint.source, stale: !await _isRepo(hint.path)));
    }

    int rank(ProjectHint h) => switch (h.source) {
      'connected' || 'active' => 0,
      _ when !h.stale => 1,
      _ => 2,
    };
    final indexed = [for (var i = 0; i < checked.length; i++) (i, checked[i])];
    indexed.sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
    return [for (final (_, hint) in indexed) hint];
  }

  /// Where the browser starts: the connected cwd, else the last folder used,
  /// else home.
  String startDirectory() =>
      connectedCwd ?? prefs.lastProjectFolder() ?? home ?? Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';

  static Future<bool> _isRepo(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return false;
    return await FileSystemEntity.type('$path/.git') != FileSystemEntityType.notFound;
  }

  @override
  String toString() => 'ProjectHints(${prefs.recentProjects().length} recent)';
}
