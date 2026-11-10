import 'dart:convert';
import 'dart:io';

/// Small per-user settings in %APPDATA%/nvimos/state.json (last seen times per repo).
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

  void _save() {
    final f = _file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_data));
    } catch (_) {}
  }
}
