import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../local/ignore_rules.dart';
import 'action_queue.dart';
import 'add_ignore.dart';

/// What the Ignore dialog decides: the scope of the rule (the file, its extension, its folder), the
/// ignore file it goes into, the rules that follow from both and the rows they cover. Built for the
/// rows the user highlighted, tracked ones included, as in Purrage: ignoring a tracked file writes
/// the rule and nothing else (untracking it is `u`). [apply] writes the rules through the shared
/// action queue and the backend's ignore-file API.
class IgnoreChoice extends ChangeNotifier {
  IgnoreChoice._(this._add, this.paths, this.targets, this._untracked) : targetIndex = _defaultTarget(targets);

  /// Load the targets of the first path, from the `.gitignore` files the backend finds. Null when
  /// the session has no backend (the ignore files live on the far side of it) or nothing is
  /// highlighted.
  static Future<IgnoreChoice?> forSelection(AddIgnoreState add) async {
    final backend = add.session.backend;
    final rows = add.actionRows;
    if (backend == null || rows.isEmpty) return null;
    final paths = {for (final r in rows) r.path}.toList();
    List<IgnoreFileRef> files;
    try {
      files = (await backend.loadIgnorePanes()).files;
      // The first load has tracked files and the project file; a nested untracked .gitignore exists
      // too, and the dialog must not say the rule will create it.
      files = [...files, ...await backend.untrackedIgnoreFiles()];
    } catch (_) {
      return null;
    }
    final existing = {
      for (final f in files)
        if (!f.exclude) f.path,
    };
    final targets = _targets(existing, paths.first);
    final untracked = [for (final r in add.rows) if (r.untracked) r.path];
    return IgnoreChoice._(add, paths, targets, untracked);
  }

  final AddIgnoreState _add;

  /// The highlighted paths, repo-relative.
  final List<String> paths;

  /// The files a rule can go into, narrowest first. Their paths are repo-relative, as the backend
  /// names them.
  final List<IgnoreTarget> targets;

  final List<String> _untracked;

  IgnoreScope scope = IgnoreScope.file;
  int targetIndex;

  IgnoreTarget get target => targets[targetIndex];

  /// The backend's name for the chosen target: a repo-relative `.gitignore`, or `.git/info/exclude`.
  IgnoreFileRef get targetRef => target.kind == IgnoreTargetKind.localExclude
      ? const IgnoreFileRef.exclude()
      : IgnoreFileRef.gitignore(target.path);

  /// The files a rule can go into for [path], narrowest first: a folder's own file (for a folder
  /// row, the one inside it), its parent folder's, the project's, then `.git/info/exclude`.
  static List<IgnoreTarget> _targets(Set<String> existing, String path) {
    final out = <IgnoreTarget>[];
    void folder(String dir) {
      final at = '$dir/.gitignore';
      if (dir.isEmpty || out.any((t) => t.path == at)) return;
      out.add(IgnoreTarget(
        kind: IgnoreTargetKind.folderGitignore,
        label: dir,
        path: at,
        dir: dir,
        exists: existing.contains(at),
      ));
    }

    final isDirectory = path.endsWith('/');
    final clean = isDirectory ? path.substring(0, path.length - 1) : path;
    if (isDirectory) folder(clean);
    final slash = clean.lastIndexOf('/');
    folder(slash < 0 ? '' : clean.substring(0, slash));
    out.add(IgnoreTarget(
      kind: IgnoreTargetKind.projectGitignore,
      label: 'project',
      path: '.gitignore',
      dir: '',
      exists: existing.contains('.gitignore'),
    ));
    out.add(const IgnoreTarget(
      kind: IgnoreTargetKind.localExclude,
      label: '.git/info/exclude (not committed)',
      path: '.git/info/exclude',
      dir: '',
      exists: true,
    ));
    return out;
  }

  /// The narrowest `.gitignore` that is already there, else the project's one (as in Purrage).
  static int _defaultTarget(List<IgnoreTarget> targets) {
    final existing = targets.indexWhere((t) => t.isCommitted && t.exists);
    if (existing >= 0) return existing;
    final project = targets.indexWhere((t) => t.kind == IgnoreTargetKind.projectGitignore);
    return project < 0 ? 0 : project;
  }

  void setScope(IgnoreScope s) {
    scope = s;
    notifyListeners();
  }

  void setTarget(int i) {
    targetIndex = i.clamp(0, targets.length - 1);
    notifyListeners();
  }

  /// j / k in the dialog: the next or previous target, stopping at the ends.
  void stepTarget(int delta) => setTarget(targetIndex + delta.sign);

  /// The base names of the paths the scope makes no rule for (an extension rule for `Makefile`).
  List<String> get missing => [
    for (final path in paths)
      if (IgnoreRules.pattern(scope: scope, targetDir: target.dir, path: path) == null) shortPath(path),
  ];

  /// How many highlighted paths the rules cover.
  int get files => paths.length - missing.length;

  /// `3 files → 1 rule`, as in Purrage.
  String get summary {
    final n = patterns.length;
    return '${files == 1 ? '1 file' : '$files files'} → ${n == 1 ? '1 rule' : '$n rules'}';
  }

  /// The rules the choice writes, one per distinct result; a path the scope cannot name (an
  /// extension rule for a file without one) gives none.
  List<String> get patterns {
    final out = <String>{};
    for (final path in paths) {
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
    // A `.gitignore` inside the folder it ignores says `*`: everything below it.
    if (plain == '*') return rel.isNotEmpty;
    if (plain.startsWith('*.')) return rel.toLowerCase().endsWith(plain.substring(1).toLowerCase());
    if (plain.startsWith('/') && plain.endsWith('/')) return rel.startsWith(plain.substring(1));
    if (plain.startsWith('/')) return rel == plain.substring(1);
    return false;
  }

  /// Why nothing can be written, or null.
  String? get problem {
    if (patterns.isEmpty) return 'this scope names nothing for ${paths.length == 1 ? 'this file' : 'these files'}';
    return null;
  }

  /// Write the rules into [target]; the rows they cover leave the list at once.
  Future<ActionResult> apply() => _add.ignoreWith(targetRef, patterns, covered: covered);

  /// The file's name for a path in the preview.
  String shortPath(String path) => path.split('/').last;

  /// The dialog's label for a target, as in Purrage; the root file is the project's.
  static String targetLabel(IgnoreTarget t) => switch (t.kind) {
    IgnoreTargetKind.folderGitignore => '.gitignore in ${t.label}',
    IgnoreTargetKind.projectGitignore => 'project .gitignore',
    IgnoreTargetKind.localExclude => t.label,
  };

  /// Whether the target is a committed file (a `.gitignore` of the repository) or a private one.
  bool get committed => target.isCommitted;
}
