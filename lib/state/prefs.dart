import 'dart:convert';
import 'dart:io';

/// Small per-user settings in %APPDATA%/nvimos/state.json (last seen times per repo, branch links,
/// view choices such as line wrapping).
class Prefs {
  Prefs._(this._file, this._data);

  final File? _file;
  final Map<String, Object?> _data;

  static Prefs load() {
    final base = Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
    if (base == null) return Prefs._(null, {});
    final f = File('$base/nvimos/state.json');
    try {
      return Prefs._(f, (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
    } catch (_) {
      return Prefs._(f, {});
    }
  }

  /// In memory only (tests).
  static Prefs memory() => Prefs._(null, {});

  /// A true / false setting, [fallback] until it was set.
  bool flag(String key, {required bool fallback}) {
    final v = (_data['flags'] as Map?)?[key];
    return v is bool ? v : fallback;
  }

  void setFlag(String key, bool value) {
    final m = ((_data['flags'] as Map?) ?? {}).cast<String, Object?>();
    m[key] = value;
    _data['flags'] = m;
    _save();
  }

  DateTime? lastSeen(String repo) {
    final v = (_data['lastSeen'] as Map?)?[repo];
    return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
  }

  void setLastSeen(String repo, DateTime t) {
    final m = ((_data['lastSeen'] as Map?) ?? {}).cast<String, Object?>();
    m[repo] = t.millisecondsSinceEpoch;
    _data['lastSeen'] = m;
    _save();
  }

  /// Branches linked to tasks by hand: task id -> branch.
  Map<String, String> branchLinks(String repo) =>
      (((_data['branchLinks'] as Map?)?[repo] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v'));

  /// Recent project folders, newest first: the local hint source when no Neovim is connected.
  List<String> recentProjects() =>
      ((_data['recentProjects'] as List?) ?? const []).map((v) => '$v').toList();

  /// Put [path] at the front of the recent projects, once.
  void rememberProject(String path) {
    final list = recentProjects()..removeWhere((p) => p.toLowerCase() == path.toLowerCase());
    list.insert(0, path);
    _data['recentProjects'] = list.take(30).toList();
    _save();
  }

  /// The folder the project browser starts in.
  String? lastProjectFolder() {
    final v = _data['lastProjectFolder'];
    return v is String ? v : null;
  }

  void setLastProjectFolder(String path) {
    _data['lastProjectFolder'] = path;
    _save();
  }

  void setBranchLinks(String repo, Map<String, String> links) {
    final m = ((_data['branchLinks'] as Map?) ?? {}).cast<String, Object?>();
    m[repo] = links;
    _data['branchLinks'] = m;
    _save();
  }

  /// The folders and addresses opened before, newest first.
  List<Recent> recents() => [
    for (final e in (_data['recent'] as List?) ?? const [])
      if (e is Map && e['target'] is String)
        Recent(e['kind'] == 'nvim' ? BackendKind.nvim : BackendKind.local, e['target'] as String),
  ];

  /// Remember [r] as the newest entry (an older copy of it goes); at most [maxRecents] are kept.
  void addRecent(Recent r) {
    final all = [r, ...recents().where((x) => x != r)].take(maxRecents);
    _setRecents(all);
  }

  void removeRecent(Recent r) => _setRecents(recents().where((x) => x != r));

  static const maxRecents = 12;

  void _setRecents(Iterable<Recent> all) {
    _data['recent'] = [
      for (final r in all) {'kind': r.kind.name, 'target': r.target},
    ];
    _save();
  }

  void _save() {
    final f = _file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_data));
    } catch (_) {}
  }
}

/// Which backend a recent entry opens with.
enum BackendKind { local, nvim }

/// A folder or a Neovim address the Connect screen remembers, with the backend it opens with.
class Recent {
  const Recent(this.kind, this.target);

  /// A folder is opened locally; an address is a Neovim with the nvimos plugin.
  final BackendKind kind;
  final String target;

  @override
  bool operator ==(Object other) => other is Recent && other.kind == kind && other.target == target;

  @override
  int get hashCode => Object.hash(kind, target);
}
