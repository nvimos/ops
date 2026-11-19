import 'package:flutter/foundation.dart';

import '../local/git_repo.dart';
import '../local/ignore_rules.dart';
import 'action_queue.dart';
import 'add_ignore.dart';

/// What the Ignore dialog decides: the scope of the rule (the file, its extension, its folder), the
/// ignore file it goes into, the rules that follow from both and the rows they cover. Built for the
/// untracked rows the user highlighted; [apply] writes the rules through the shared action queue.
class IgnoreChoice extends ChangeNotifier {
  IgnoreChoice._(this._add, this.paths, this.targets, this.already, this._untracked);

  /// Load the targets of the first path and which paths git already ignores. Null when the
  /// session has no local repository (the rules engine works on its files).
  static Future<IgnoreChoice?> forSelection(AddIgnoreState add) async {
    final repo = add.repo;
    final rows = add.actionRows.where((r) => r.untracked).toList();
    if (repo == null || rows.isEmpty) return null;
    final paths = {for (final r in rows) r.path}.toList();
    final targets = IgnoreRules.targets(
      repoPath: repo.path,
      gitignoreFiles: await repo.gitignoreFiles(),
      localExclude: await repo.localExcludePath(),
      globalIgnore: await repo.globalIgnorePath(),
      path: paths.first,
    );
    final already = await repo.checkIgnoreAll(paths);
    final untracked = [for (final r in add.rows) if (r.untracked) r.path];
    return IgnoreChoice._(add, paths, targets, already, untracked);
  }

  final AddIgnoreState _add;

  /// The highlighted untracked paths, repo-relative.
  final List<String> paths;

  /// The files a rule can go into, narrowest first.
  final List<IgnoreTarget> targets;

  /// Paths git already ignores, with the rule that does it: named before the click.
  final Map<String, IgnoreMatch> already;

  final List<String> _untracked;

  IgnoreScope scope = IgnoreScope.file;
  int targetIndex = 0;

  IgnoreTarget get target => targets[targetIndex];

  void setScope(IgnoreScope s) {
    scope = s;
    notifyListeners();
  }

  void setTarget(int i) {
    targetIndex = i.clamp(0, targets.length - 1);
    notifyListeners();
  }

  /// The rules the choice writes, one per distinct result; a path the scope cannot name (an
  /// extension rule for a file without one) gives none.
  List<String> get patterns {
    final out = <String>{};
    for (final path in paths) {
      if (already.containsKey(path)) continue;
      final p = IgnoreRules.pattern(scope: scope, targetDir: target.dir, path: path);
      if (p != null) out.add(p);
    }
    return out.toList();
  }

  /// The untracked rows the rules would take off the list.
  List<String> get covered => [
    for (final path in _untracked)
      if (patterns.any((p) => _covers(p, path))) path,
  ];

  /// Whether [pattern] (as the rules engine builds it) names [path], for the shapes it builds: a
  /// file `/a/b.txt`, a folder `/a/`, an extension `*.log`; relative to the ignore file's folder.
  bool _covers(String pattern, String path) {
    final dir = target.dir;
    if (dir.isNotEmpty && !path.startsWith('$dir/')) return false;
    final rel = dir.isEmpty ? path : path.substring(dir.length + 1);
    final plain = pattern.replaceAll(RegExp(r'\\(.)'), r'$1');
    if (plain.startsWith('*.')) return rel.toLowerCase().endsWith(plain.substring(1).toLowerCase());
    if (plain.startsWith('/') && plain.endsWith('/')) return rel.startsWith(plain.substring(1));
    if (plain.startsWith('/')) return rel == plain.substring(1);
    return false;
  }

  /// Why nothing can be written, or null.
  String? get problem {
    if (paths.every(already.containsKey)) return 'git already ignores ${paths.length == 1 ? 'it' : 'all of them'}';
    if (patterns.isEmpty) return 'this scope names nothing for ${paths.length == 1 ? 'this file' : 'these files'}';
    return null;
  }

  /// Write the rules into [target]; the rows they cover leave the list at once.
  Future<ActionResult> apply() => _add.ignoreWith(target.path, patterns, covered: covered);

  /// The file's name for a path in the preview.
  String shortPath(String path) => path.split('/').last;

  String labelOf(IgnoreMatch m) => '${m.pattern}  in ${m.source.split(RegExp(r'[\\/]')).last}:${m.line}';

  /// Whether the target is a committed file (a `.gitignore` of the repository) or a private one.
  bool get committed => target.isCommitted;
}
