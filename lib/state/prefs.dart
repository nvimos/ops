import 'dart:convert';
import 'dart:io';

/// Small per-user settings in %APPDATA%/nvimos/state.json (last seen times per repo, branch links,
/// view choices such as line wrapping).
class Prefs {
  Prefs._(this._file, this._data, {this.recoveryNotice});

  final File? _file;
  final Map<String, Object?> _data;

  /// Why a broken state file was kept aside, or left in place. Null when the file was missing or
  /// valid; the app shows this once in the notice bar.
  final String? recoveryNotice;

  /// Where [load] reads and writes instead of %APPDATA% (tests: a temp folder, so a test never
  /// touches the user's state.json).
  static String? baseOverride;

  /// Read the state file. A missing file is a fresh start. A file that cannot be read, or is not a
  /// JSON object, is renamed to `state.json.bad-<yyyy-mm-dd-HHmmss>` first; [recoveryNotice] names it.
  static Prefs load() {
    final base = baseOverride ?? Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
    if (base == null) return Prefs._(null, {});
    final f = File('$base/nvimos/state.json');
    if (!f.existsSync()) return Prefs._(f, {});
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is Map) return Prefs._(f, decoded.cast<String, Object?>());
    } catch (_) {
      if (!f.existsSync()) return Prefs._(f, {});
    }
    return _keepBroken(f);
  }

  /// The file is there but not settings. Move it aside before a save can replace it. If the move
  /// fails, drop the path so a later save cannot write `{}` over the original bytes.
  static Prefs _keepBroken(File f) {
    final aside = _asideFile(f);
    if (aside != null) {
      try {
        f.renameSync(aside.path);
        return Prefs._(f, {}, recoveryNotice: 'Settings file could not be read. The old file was kept at ${aside.path}');
      } catch (_) {}
    }
    return Prefs._(null, {}, recoveryNotice: 'Settings file could not be read and was left in place: ${f.path}');
  }

  /// A free `state.json.bad-<yyyy-mm-dd-HHmmss>` beside [f]. A taken name gets a numeric suffix.
  static File? _asideFile(File f) {
    final stamp = _badStamp(DateTime.now());
    final dir = f.parent.path;
    final sep = Platform.pathSeparator;
    for (var n = 0; n < 1000; n++) {
      final suffix = n == 0 ? '' : '-${n + 1}';
      final candidate = File('$dir${sep}state.json.bad-$stamp$suffix');
      if (!candidate.existsSync()) return candidate;
    }
    return null;
  }

  static String _badStamp(DateTime t) {
    String p(int n, int w) => n.toString().padLeft(w, '0');
    return '${p(t.year, 4)}-${p(t.month, 2)}-${p(t.day, 2)}-${p(t.hour, 2)}${p(t.minute, 2)}${p(t.second, 2)}';
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

  /// A list of strings under [key] (the rail's mode order and hidden modes). A missing key, or one
  /// that holds something else after a hand edit or an older format, reads as empty.
  List<String> strings(String key) {
    final value = _data[key];
    return value is List ? [for (final e in value) '$e'] : const [];
  }

  void setStrings(String key, List<String> value) {
    _data[key] = value;
    _save();
  }

  /// Put [path] at the front of the recent projects, once.
  void rememberProject(String path) {
    final list = recentProjects()..removeWhere((p) => p.toLowerCase() == path.toLowerCase());
    list.insert(0, path);
    _data['recentProjects'] = list.take(30).toList();
    _save();
  }

  /// Drop [path] from the recent projects (a stale hint the user removed).
  void forgetProject(String path) {
    _data['recentProjects'] = (recentProjects()..removeWhere((p) => p.toLowerCase() == path.toLowerCase()));
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

  /// A text setting from Settings (the editor command, the terminal id), null until chosen.
  String? text(String key) {
    final v = (_data['settings'] as Map?)?[key];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  /// Save a text setting; null (or blank) clears it, so detection decides again.
  void setText(String key, String? value) => _setting(key, value == null || value.trim().isEmpty ? null : value.trim());

  /// A number setting from Settings (the crawl depth), null until chosen.
  int? number(String key) {
    final v = (_data['settings'] as Map?)?[key];
    return v is int ? v : null;
  }

  void setNumber(String key, int value) => _setting(key, value);

  void _setting(String key, Object? value) {
    final m = ((_data['settings'] as Map?) ?? {}).cast<String, Object?>();
    value == null ? m.remove(key) : m[key] = value;
    _data['settings'] = m;
    _save();
  }

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

/// The keys of the settings the Settings mode edits (see [Prefs.text] and [Prefs.number]), the flags
/// behind its on / off choices (see [Prefs.flag]), and the two the Add and Ignore pane keeps.
abstract final class Settings {
  /// The editor command with `{file}` and `{line}`; unset: the first detected editor.
  static const editorKey = 'editorCommand';

  /// The terminal's id from the known list; unset: the first detected one.
  static const terminalKey = 'terminalId';

  /// Who opens a folder: `editor`, else the system's file manager.
  static const folderOpenerKey = 'folderOpener';

  /// How many levels below its start folder the crawl goes.
  static const scanDepthKey = 'scanDepth';

  /// Rows one Shift + wheel notch (or one step of the wheel mode) moves a list; 2 to 1000, 5.
  static const wheelStepKey = 'wheelStep';
  static const wheelStepMin = 2;
  static const wheelStepMax = 1000;
  static const wheelStepDefault = 5;

  /// Delete into the trash (the flag unset: on) instead of removing for good.
  static const deleteToTrashFlag = 'deleteToTrash';

  /// Ask before deleting (the flag unset: no question, as in Purrage).
  static const confirmDeleteFlag = 'confirmDelete';

  /// What the Add and Ignore side pane shows: `preview`, else the ignore rules.
  static const sideViewKey = 'sideView';

  /// The Add and Ignore side pane's width in pixels, as it was last dragged; unset: 360.
  static const sidePaneWidthKey = 'sidePaneWidth';
}
