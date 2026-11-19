import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../local/ignore_edits.dart';
import 'add_ignore.dart';

/// What a line edit came to: a done message and its Undo, or the refusal to say.
class IgnoreEdit {
  const IgnoreEdit.done(String this.message, [this.undo]) : refusal = null;
  const IgnoreEdit.refused(String this.refusal) : message = null, undo = null;

  final String? message;
  final String? refusal;

  /// Puts the line back; the next edit replaces this one (one notice at a time).
  final IgnoreUndo? undo;

  bool get ok => refusal == null;
}

/// Undo an edit; a refusal means the file changed under it.
typedef IgnoreUndo = Future<IgnoreEdit> Function();

/// The two Ignore panes: every `.gitignore` of the project, and every line of the selected one.
///
/// The files are read once when the panes open (one `loadIgnorePanes` call, then the untracked ones
/// when they arrive), and again only when the status lists a different `.gitignore` path or after
/// the app's own write. Moving the cursor reads nothing; picking another file reads only that file.
/// While hidden nothing is read: the pane marks itself stale and loads when shown again.
class IgnorePaneState extends ChangeNotifier {
  IgnorePaneState(this._add) {
    _add.store.refreshed.addListener(_onRefreshed);
    _add.ignoreWrites.addListener(_onWrite);
    unawaited(load());
  }

  final AddIgnoreState _add;

  List<IgnoreFileRef> _files = const [];
  IgnoreFileRef? _selected;
  String _text = '';
  List<String> _lines = const [];
  int _lineCursor = 0; // 1-based, 0 when the file is empty
  String? error;
  bool loading = false;

  bool _visible = true;
  bool _stale = false;
  bool _disposed = false;
  int _gen = 0;

  /// How many list loads and single-file reads the pane made (tests: a cursor move makes none).
  int loads = 0, reads = 0;

  Set<String> _seenStatus = const {};
  IgnoreWrite? _pendingWrite;

  /// A request to centre a line: the pane bumps [centreRequest] and the view centres
  /// [centreLine]. No animation.
  int centreRequest = 0;
  int centreLine = 0;

  AddIgnoreState get add => _add;

  /// Every `.gitignore` of the project, the project one first.
  List<IgnoreFileRef> get files => _files;

  /// The file shown on the right, kept across reloads and the session.
  IgnoreFileRef? get selected => _selected;

  /// The selected file's text and its lines, as they are (comments and blanks too).
  String get text => _text;
  List<String> get lines => _lines;

  /// The line cursor, 1-based; 0 when the file is empty.
  int get lineCursor => _lineCursor;

  /// The line under the cursor, or null.
  String? get currentLine => _lineCursor >= 1 && _lineCursor <= _lines.length ? _lines[_lineCursor - 1] : null;

  bool get visible => _visible;
  bool get stale => _stale;
  bool get available => _add.session.backend != null;

  /// The files that govern the cursor row's folder: the project file and the ones at or above it.
  /// A string-prefix check per file, no git; the selection does not follow it.
  Set<String> get governing {
    final row = _add.selected;
    if (row == null) return const {};
    final folder = row.isDirectory ? _cleanPath(row.path) : row.folder;
    return {
      for (final f in _files)
        if (_governs(f, folder)) f.path,
    };
  }

  static bool _governs(IgnoreFileRef f, String folder) {
    if (f.exclude) return false;
    if (f.path == '.gitignore') return true;
    const suffix = '/.gitignore';
    if (!f.path.endsWith(suffix)) return false;
    final dir = f.path.substring(0, f.path.length - suffix.length);
    return dir.isNotEmpty && (folder == dir || folder.startsWith('$dir/'));
  }

  /// A short name for the list: `project .gitignore` for the root file, its folder for a nested one.
  static String labelOf(IgnoreFileRef f) {
    if (f.path == '.gitignore') return 'project .gitignore';
    const suffix = '/.gitignore';
    return f.path.endsWith(suffix) ? f.path.substring(0, f.path.length - suffix.length) : f.path;
  }

  // Showing ---------------------------------------------------------------------------------------

  /// The pane was shown or hidden by the switch. Hidden: mark stale and read nothing until shown.
  void setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    if (!value) {
      _stale = true;
      return;
    }
    if (_stale) {
      _stale = false;
      unawaited(load());
      return;
    }
    final pending = _pendingWrite;
    if (pending != null) {
      _pendingWrite = null;
      unawaited(_applyWrite(pending));
    }
  }

  // Reading ---------------------------------------------------------------------------------------

  /// Read the file list and the selected file's text in one call, then the untracked files.
  Future<void> load() async {
    if (!_visible) {
      _stale = true;
      return;
    }
    final b = _add.session.backend;
    if (b == null) {
      error = 'ignore needs a repository';
      notifyListeners();
      return;
    }
    final gen = ++_gen;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final snap = await b.loadIgnorePanes(selected: _selected);
      if (gen != _gen || _disposed) return;
      loads++;
      _files = _sort(_merge(snap.files, _selected));
      _selected = _choose(snap.selected);
      final inOneCall = snap.text != null && snap.selected != null && _same(snap.selected, _selected);
      if (inOneCall) _setText(snap.text!);
      _seenStatus = _statusIgnores();
      loading = false;
      notifyListeners();
      if (!inOneCall && _selected != null) await _readSelected(gen);
      if (gen != _gen || _disposed) return;
      unawaited(_addUntracked(gen));
      final pending = _pendingWrite;
      if (pending != null) {
        _pendingWrite = null;
        unawaited(_applyWrite(pending));
      }
    } catch (e) {
      if (gen != _gen || _disposed) return;
      error = '$e';
      loading = false;
      notifyListeners();
    }
  }

  /// The untracked `.gitignore` files, added when they arrive; the tracked ones already show.
  Future<void> _addUntracked(int gen) async {
    final b = _add.session.backend;
    if (b == null) return;
    try {
      final extra = await b.untrackedIgnoreFiles();
      if (gen != _gen || _disposed) return;
      final merged = _sort(_merge([..._files, ...extra], _selected));
      if (merged.length == _files.length) return;
      _files = merged;
      // Only nested untracked files: the first call had no file to show, so take the first now.
      if (_selected == null && merged.isNotEmpty) {
        _selected = merged.first;
        await _readSelected(gen);
      }
      notifyListeners();
    } catch (_) {
      // A discovery failure leaves the tracked list on screen.
    }
  }

  /// Pick a file in the list: reads only that file.
  Future<void> pick(IgnoreFileRef file) async {
    if (_same(file, _selected)) return;
    _selected = file;
    _text = '';
    _lines = const [];
    _lineCursor = 0;
    loading = false;
    notifyListeners();
    if (!_visible) {
      _stale = true;
      return;
    }
    await _readSelected(++_gen);
  }

  /// j / k in the file list: next or previous file, clamped.
  Future<void> moveFile(int delta) async {
    if (_files.isEmpty) return;
    final at = _files.indexWhere((f) => _same(f, _selected));
    final next = ((at < 0 ? 0 : at) + delta).clamp(0, _files.length - 1);
    await pick(_files[next]);
  }

  void moveLine(int delta) {
    if (_lines.isEmpty || delta == 0) return;
    final at = _lineCursor < 1 ? 1 : _lineCursor;
    _lineCursor = (at + delta).clamp(1, _lines.length);
    notifyListeners();
  }

  /// A click or a Tab into the lines: put the cursor on [line] (1-based).
  void pickLine(int line) {
    if (_lines.isEmpty) return;
    _lineCursor = line.clamp(1, _lines.length);
    notifyListeners();
  }

  Future<void> _readSelected(int gen) async {
    final file = _selected;
    final b = _add.session.backend;
    if (file == null || b == null) return;
    try {
      final text = await b.readIgnoreFile(file);
      if (gen != _gen || _disposed) return;
      reads++;
      _setText(text);
      notifyListeners();
    } catch (e) {
      if (gen != _gen || _disposed) return;
      error = '$e';
      notifyListeners();
    }
  }

  void _setText(String text) {
    _text = text;
    _lines = _splitLines(text);
    _lineCursor = _lines.isEmpty ? 0 : _lineCursor.clamp(1, _lines.length);
    if (_lines.isNotEmpty && _lineCursor == 0) _lineCursor = 1;
  }

  // Status and its own writes ---------------------------------------------------------------------

  void _onRefreshed() {
    if (!_visible) {
      _stale = true;
      return;
    }
    if (!setEquals(_statusIgnores(), _seenStatus)) unawaited(load());
  }

  Set<String> _statusIgnores() => {
    for (final f in _add.store.status?.files ?? const <StatusFile>[])
      if (f.path == '.gitignore' || f.path.endsWith('/.gitignore')) f.path,
  };

  void _onWrite() {
    final write = _add.ignoreWrites.value;
    if (write == null) return;
    if (!_visible) {
      _pendingWrite = write;
      _stale = true;
      return;
    }
    unawaited(_applyWrite(write));
  }

  /// After the app's own write: select its file and centre the first new rule it added. A write to
  /// `.git/info/exclude` is not a `.gitignore` in the list, so nothing is selected for it.
  Future<void> _applyWrite(IgnoreWrite write) async {
    if (write.file.exclude) return;
    if (loading) {
      _pendingWrite = write;
      return;
    }
    _selected = write.file;
    loading = false;
    if (!_files.any((f) => _same(f, write.file))) {
      _files = _sort([..._files, write.file]);
    }
    await _readSelected(++_gen);
    if (_disposed) return;
    final added = [for (final a in write.appends) a == IgnoreAppend.added];
    final line = IgnoreEdits.lineAfterWrite(_text, write.patterns, added: added);
    if (line != null) {
      _lineCursor = line;
      centreRequest++;
      centreLine = line;
    }
    notifyListeners();
  }

  // Line edits ------------------------------------------------------------------------------------

  /// Delete line [number]; Undo puts it back with `insertIgnoreLine`.
  Future<IgnoreEdit> deleteLine(int number) {
    final line = _lineAt(number);
    if (line == null) return Future.value(IgnoreEdit.refused(_notThere(number)));
    return _replace(number, line, null, 'deleted line $number from ${_selected!.path}');
  }

  /// Dirname: take the rule one folder up; when the parent rule is already there, remove the line.
  Future<IgnoreEdit> dirnameLine(int number) {
    final line = _lineAt(number);
    if (line == null) return Future.value(IgnoreEdit.refused(_notThere(number)));
    final up = IgnoreEdits.dirname(line);
    if (!up.ok) return Future.value(IgnoreEdit.refused(up.refusal!));
    final replacement = _lines.contains(up.text) ? null : up.text;
    final summary = replacement == null
        ? 'removed line $number (the parent rule is already there)'
        : 'moved line $number to ${up.text}';
    return _replace(number, line, replacement, summary);
  }

  /// Flip: toggle the rule's leading `!`.
  Future<IgnoreEdit> flipLine(int number) {
    final line = _lineAt(number);
    if (line == null) return Future.value(IgnoreEdit.refused(_notThere(number)));
    final flip = IgnoreEdits.flip(line);
    if (!flip.ok) return Future.value(IgnoreEdit.refused(flip.refusal!));
    return _replace(number, line, flip.text, 'flipped line $number to ${flip.text}');
  }

  /// The line's refusal for a disabled Dirname item, or null when it can run.
  static String? dirnameRefusal(String line) => IgnoreEdits.dirname(line).refusal;

  /// The line's refusal for a disabled Flip item, or null when it can run.
  static String? flipRefusal(String line) => IgnoreEdits.flip(line).refusal;

  Future<IgnoreEdit> _replace(int number, String expected, String? replacement, String summary) async {
    final file = _selected;
    final b = _add.session.backend;
    if (file == null) return const IgnoreEdit.refused('no ignore file selected');
    if (b == null) return const IgnoreEdit.refused('ignore needs a repository');
    final before = _add.store.status?.files ?? const <StatusFile>[];
    final written = await b.replaceIgnoreLine(file, number, expected, replacement);
    if (!written) return IgnoreEdit.refused('${file.path} changed: line $number is no longer `$expected`');
    final afterText = await _readAfterWrite(file);
    final after = await _refreshStatus();
    final undo = replacement == null
        ? () => _undoInsert(file, number, expected, afterText)
        : () => _undoReplace(file, number, replacement, expected, afterText);
    return IgnoreEdit.done(_withEffect(summary, before, after), undo);
  }

  /// Undo of a Delete (or of a Dirname that removed the line): insert it back, refusing when the
  /// file changed under the edit.
  Future<IgnoreEdit> _undoInsert(IgnoreFileRef file, int number, String text, String afterText) async {
    final b = _add.session.backend;
    if (b == null) return const IgnoreEdit.refused('ignore needs a repository');
    final current = await b.readIgnoreFile(file);
    if (current != afterText) return IgnoreEdit.refused('${file.path} changed since the edit');
    final at = number.clamp(1, _splitLines(current).length + 1);
    await b.insertIgnoreLine(file, at, text);
    await _readAfterWrite(file);
    await _refreshStatus();
    return IgnoreEdit.done('restored line $at');
  }

  /// Undo of Dirname or Flip: write the old line back over the new one.
  Future<IgnoreEdit> _undoReplace(IgnoreFileRef file, int number, String current, String old, String afterText) async {
    final b = _add.session.backend;
    if (b == null) return const IgnoreEdit.refused('ignore needs a repository');
    final written = await b.replaceIgnoreLine(file, number, current, old);
    if (!written) return IgnoreEdit.refused('${file.path} changed since the edit');
    await _readAfterWrite(file);
    await _refreshStatus();
    return IgnoreEdit.done('restored line $number');
  }

  Future<String> _readAfterWrite(IgnoreFileRef file) async {
    final b = _add.session.backend;
    if (b == null) return _text;
    final text = await b.readIgnoreFile(file);
    reads++;
    if (_same(_selected, file)) _setText(text);
    notifyListeners();
    return text;
  }

  /// The status the app reads after its own write. The refresh that follows the write is the
  /// watcher's; waiting for it (or one of our own when it is slow) keeps the effect honest without a
  /// git call of its own. No `check-ignore`, no extra status besides the one the store would make.
  Future<List<StatusFile>> _refreshStatus() async {
    final store = _add.store;
    final seen = store.refreshed.value;
    final next = Completer<void>();
    void onRefresh() {
      if (!next.isCompleted) next.complete();
    }

    store.refreshed.addListener(onRefresh);
    try {
      await next.future.timeout(const Duration(milliseconds: 500), onTimeout: () {});
      if (store.refreshed.value == seen) await store.refresh();
    } finally {
      store.refreshed.removeListener(onRefresh);
    }
    return store.status?.files ?? const <StatusFile>[];
  }

  // Files ----------------------------------------------------------------------------------------

  /// New here: a `.gitignore` in the cursor row's folder (inside a directory row, at the root for
  /// a file at the root), through the backend.
  Future<IgnoreEdit> createHere() => _create(
    IgnoreFileRef.gitignore(switch (_add.selected) {
      null => '.gitignore',
      final row when row.isDirectory => '${_cleanPath(row.path)}/.gitignore',
      final row => row.folder.isEmpty ? '.gitignore' : '${row.folder}/.gitignore',
    }),
  );

  /// The empty state's button: the project `.gitignore` at the root.
  Future<IgnoreEdit> createProject() => _create(const IgnoreFileRef.gitignore('.gitignore'));

  Future<IgnoreEdit> _create(IgnoreFileRef file) async {
    final b = _add.session.backend;
    if (b == null) return const IgnoreEdit.refused('ignore needs a repository');
    try {
      await b.createIgnoreFile(file);
    } catch (e) {
      return IgnoreEdit.refused('$e');
    }
    _selected = file;
    if (!_files.any((f) => _same(f, file))) _files = _sort([..._files, file]);
    await _readSelected(++_gen);
    await _add.store.refresh();
    return IgnoreEdit.done('created ${file.path}');
  }

  /// Open the selected file in the editor at [line] (1-based).
  Future<IgnoreEdit> openSelected({int line = 1}) async {
    final file = _selected;
    if (file == null) return const IgnoreEdit.refused('no ignore file selected');
    final editor = _add.session.editor;
    if (editor == null) return const IgnoreEdit.refused('open needs an editor');
    try {
      await editor.open(file.path, line.clamp(1, 1 << 20));
    } catch (e) {
      return IgnoreEdit.refused('$e');
    }
    return IgnoreEdit.done('opened ${file.path}');
  }

  /// Open the file at the line cursor.
  Future<IgnoreEdit> openLine() => openSelected(line: _lineCursor < 1 ? 1 : _lineCursor);

  // Helpers --------------------------------------------------------------------------------------

  String? _lineAt(int number) => number >= 1 && number <= _lines.length ? _lines[number - 1] : null;

  String _notThere(int number) => 'line $number is not in ${_selected?.path ?? 'the file'} any more';

  String _withEffect(String summary, List<StatusFile> before, List<StatusFile> after) {
    final effect = IgnoreEffect.between(before, after).message;
    return effect == null ? summary : '$summary · $effect';
  }

  IgnoreFileRef? _choose(IgnoreFileRef? fromBackend) {
    if (_selected != null && _files.any((f) => _same(f, _selected))) return _selected;
    if (fromBackend != null) return fromBackend;
    if (_files.isEmpty) return null;
    return _files.first; // the project file, else the first one
  }

  static List<IgnoreFileRef> _merge(List<IgnoreFileRef> files, IgnoreFileRef? extra) {
    final out = <IgnoreFileRef>[];
    void add(IgnoreFileRef f) {
      if (out.any((e) => _same(e, f))) return;
      out.add(f);
    }

    for (final f in files) {
      add(f);
    }
    if (extra != null) add(extra);
    return out;
  }

  /// The project file first, then the rest by path.
  static List<IgnoreFileRef> _sort(List<IgnoreFileRef> files) {
    final out = [...files];
    out.sort((a, b) {
      if (a.path == '.gitignore' && b.path != '.gitignore') return -1;
      if (b.path == '.gitignore' && a.path != '.gitignore') return 1;
      final byPath = a.path.compareTo(b.path);
      if (byPath != 0) return byPath;
      return a.exclude == b.exclude ? 0 : (a.exclude ? 1 : -1);
    });
    return List.unmodifiable(out);
  }

  static bool _same(IgnoreFileRef? a, IgnoreFileRef? b) =>
      a != null && b != null && a.path == b.path && a.exclude == b.exclude;

  static String _cleanPath(String path) => path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  static List<String> _splitLines(String text) {
    if (text.isEmpty) return const [];
    final lines = text.split(RegExp(r'\r\n|\n'));
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _add.store.refreshed.removeListener(_onRefreshed);
    _add.ignoreWrites.removeListener(_onWrite);
    super.dispose();
  }
}
