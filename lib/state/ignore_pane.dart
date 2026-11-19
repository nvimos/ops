import 'dart:async';

import 'package:flutter/foundation.dart';

import '../local/git_repo.dart';
import '../local/ignore_rules.dart';
import '../local/repo.dart';
import 'add_ignore.dart';

/// One rule line of an ignore file: its number (1-based) and text.
class IgnoreLine {
  const IgnoreLine(this.number, this.text);

  final int number;
  final String text;
}

/// An ignore file that governs a path, with the rules in it.
class IgnoreFileView {
  const IgnoreFileView(this.target, this.lines);

  final IgnoreTarget target;
  final List<IgnoreLine> lines;
}

/// What the pane shows for one path: the ignore files around it, and the rule that decides it.
class IgnoreInfo {
  const IgnoreInfo(this.path, this.files, this.match);

  final String path;
  final List<IgnoreFileView> files;

  /// The rule git says ignores [path], or null when none does.
  final IgnoreMatch? match;

  bool isMatch(IgnoreFileView f, IgnoreLine l) =>
      match != null && match!.line == l.number && _same(match!.source, f.target.path);

  static bool _same(String a, String b) => a.replaceAll(r'\', '/').toLowerCase() == b.replaceAll(r'\', '/').toLowerCase();
}

/// The Ignore pane of the Add and Ignore mode: the ignore files around the row under the cursor and
/// the rule that matches it. It follows the cursor without a git call per key press: the answer for
/// a path is looked up once the cursor has rested for [delay], and kept until the list reloads.
class IgnorePaneState extends ChangeNotifier {
  /// [lookup] answers for a path instead of the repository (tests).
  IgnorePaneState(this._add, {this.delay = const Duration(milliseconds: 200), Future<IgnoreInfo> Function(String path)? lookup})
    // ignore: prefer_initializing_formals
    : _lookup = lookup {
    _add.addListener(_onAdd);
    _add.store.refreshed.addListener(forget); // a reload may follow a rule written elsewhere
    _onAdd();
  }

  final AddIgnoreState _add;
  final Duration delay;
  final Future<IgnoreInfo> Function(String path)? _lookup;

  IgnoreInfo? info;
  String? error;
  bool loading = false;

  final _cache = <String, IgnoreInfo>{};
  Timer? _timer;
  String? _wanted;
  int _lookups = 0;
  bool _disposed = false;

  /// How many times git was asked (for tests: a cursor walk asks once, at rest).
  int get lookups => _lookups;

  Repo? get repo => _add.repo;

  /// The pane has something to ask: a local repository (or, in tests, a lookup of its own).
  bool get available => _lookup != null || repo != null;

  /// The path the pane is about: the row under the cursor.
  String? get path => _add.selected?.path;

  void _onAdd() {
    final p = path;
    if (p == _wanted) return;
    _wanted = p;
    _timer?.cancel();
    final cached = p == null ? null : _cache[p];
    if (p == null || !available) {
      info = null;
      loading = false;
      notifyListeners();
    } else if (cached != null) {
      info = cached;
      loading = false;
      notifyListeners();
    } else {
      loading = true;
      notifyListeners();
      _timer = Timer(delay, () => _load(p));
    }
  }

  Future<IgnoreInfo> _fromRepo(String p) async {
    final r = repo!;
    final targets = IgnoreRules.targets(
      repoPath: r.path,
      gitignoreFiles: await r.gitignoreFiles(),
      localExclude: await r.localExcludePath(),
      globalIgnore: await r.globalIgnorePath(),
      path: p,
    );
    final files = [for (final t in targets) IgnoreFileView(t, _rules(await r.readTextFile(t.path)))];
    return IgnoreInfo(p, files, await r.checkIgnore(p));
  }

  Future<void> _load(String p) async {
    if (!available || _disposed) return;
    _lookups++;
    try {
      final loaded = await (_lookup ?? _fromRepo)(p);
      _cache[p] = loaded;
      error = null;
      if (_wanted == p) info = loaded;
    } catch (e) {
      error = '$e';
    }
    if (_wanted == p) loading = false;
    notifyListeners();
  }

  /// The lines that are rules: not blank, not comments.
  static List<IgnoreLine> _rules(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    return [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].trim().isNotEmpty && !lines[i].trimLeft().startsWith('#')) IgnoreLine(i + 1, lines[i]),
    ];
  }

  /// The ignore files changed under us (a rule was written, the list reloaded): ask again.
  void forget() {
    _cache.clear();
    final p = _wanted;
    _wanted = null;
    if (p != null) _onAdd();
  }

  /// Remove [line] from [file]; false when the file changed since it was read.
  Future<bool> deleteRule(IgnoreFileView file, IgnoreLine line) => _edit(file, line, null);

  /// Replace [line] by the same rule one folder up (`/a/b/` becomes `/a/`); false when the rule
  /// has no parent folder, or the file changed.
  Future<bool> ruleOneFolderUp(IgnoreFileView file, IgnoreLine line) {
    final up = IgnoreRules.dirname(line.text);
    return up == null ? Future.value(false) : _edit(file, line, up);
  }

  bool canMoveUp(IgnoreLine line) => IgnoreRules.dirname(line.text) != null;

  Future<bool> _edit(IgnoreFileView file, IgnoreLine line, String? replacement) async {
    final r = repo;
    if (r == null) return false;
    final done = await r.replaceIgnoreLine(file.target.path, line.number, line.text, replacement);
    forget();
    await _add.store.refresh();
    return done;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _add.removeListener(_onAdd);
    _add.store.refreshed.removeListener(forget);
    super.dispose();
  }
}
