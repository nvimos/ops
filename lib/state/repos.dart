import 'dart:io';

import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../backend/repo_backend.dart';
import '../local/browser.dart';
import '../local/paths.dart';
import '../local/project_hints.dart';
import 'nvim_launcher.dart';
import 'prefs.dart';
import 'session.dart';

/// The mode a project opens in: the first one with something to do.
enum OpenTarget { pullRequest, changes, tasks }

/// A branch other than the default one means a pull request to review; else uncommitted changes
/// mean work to stage; else the tasks, even when there are none.
OpenTarget openTarget(Branches branches, Status status) {
  final names = branches.list.map((b) => b.name).toSet();
  final main = names.contains('main') ? 'main' : (names.contains('master') ? 'master' : branches.current);
  if (names.any((n) => n != main)) return OpenTarget.pullRequest;
  if (status.files.isNotEmpty) return OpenTarget.changes;
  return OpenTarget.tasks;
}

/// One row of the Repos list: a repository, and where we heard of it.
class RepoEntry {
  const RepoEntry(this.path, {required this.source, this.stale = false});

  final String path;

  /// `connected`, `active`, `startdirs`, `recent` (a hint) or `found` (the crawl).
  final String source;

  /// A hint whose folder is gone or is no repository any more: shown greyed, with Remove.
  final bool stale;
}

/// State of the Repos mode: the repositories the crawler finds, ordered by the hints (the open
/// repository, the start dirs of a connected Neovim, the recent folders), a filter, and opening one.
/// It needs no Neovim: the start dirs are one optional hint source.
class ReposState extends ChangeNotifier {
  ReposState(this.session, {this.launch = launchNeovim, RepoBrowser? browser, ProjectHints? hints})
    // ignore: prefer_initializing_formals
    : _hints = hints,
      _browserOverride = browser {
    session.addListener(_onSession);
    _onSession();
  }

  final Session session;

  /// Starts a Neovim listening on [address] in [dir] with the backend plugin at [pluginRoot].
  final Future<void> Function(String dir, String address, String pluginRoot) launch;

  final ProjectHints? _hints;
  final RepoBrowser? _browserOverride;

  /// The crawler: walks from [ProjectHints.startDirectory].
  late final RepoBrowser browser = _browserOverride ?? RepoBrowser(startDirectory: _hintsNow().startDirectory());

  /// The start dirs of the connected backend, when it has any (a Neovim with genja-startdirs).
  StartDirs? dirs;
  List<ProjectHint> hints = const [];
  String filter = '';
  int cursor = 0;
  bool loading = false;
  String? error;

  /// Picking a dir starts a new Neovim there instead of moving the connected one.
  bool newNeovim = false;

  bool _disposed = false;
  bool _started = false;
  int _loadGen = 0;

  ProjectHints _hintsNow() =>
      _hints ??
      ProjectHints(
        prefs: session.prefs,
        connectedCwd: session.repo?.cwd,
        active: session.repo?.root,
        startDirs: _startDirs,
      );

  Future<List<String>> _startDirs() async {
    final b = session.backend;
    if (b == null || session.kind == BackendKind.local) return const [];
    try {
      dirs = await b.dirs();
      return dirs!.dirs;
    } catch (_) {
      return const []; // the call is optional: no genja-startdirs, no hints from it
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// The Active Directory: where the open repository is.
  String? get active => session.repo?.cwd;

  /// The hints first (stale ones last of them), then what the crawl found besides.
  List<RepoEntry> get entries {
    final seen = <String>{};
    final out = <RepoEntry>[];
    void add(String path, String source, {bool stale = false}) {
      if (seen.add(canonicalPath(path).toLowerCase())) out.add(RepoEntry(path, source: source, stale: stale));
    }

    for (final h in hints) {
      add(h.path, h.source, stale: h.stale);
    }
    for (final r in browser.repos) {
      add(r, 'found');
    }
    return out;
  }

  /// The entries the filter lets through.
  List<RepoEntry> get shownEntries {
    final q = filter.trim().toLowerCase();
    final all = entries;
    return q.isEmpty ? all : [for (final e in all) if (e.path.toLowerCase().contains(q)) e];
  }

  List<String> get shown => [for (final e in shownEntries) e.path];

  void _onSession() {
    if (!_started) {
      _started = true;
      browser.addListener(notifyListeners);
      final before = browser.onReport;
      browser.onReport = (r) {
        before?.call(r);
        lastReport = r;
        notifyListeners();
      };
      load();
    }
  }

  /// What the last walk did (where from, how far, how long), for the line under the title.
  ScanReport? lastReport;

  /// The folder the crawl walks from.
  String get crawlFolder => browser.directory;

  /// Walk from [path] instead (a folder chosen in the list, the parent, a drive).
  Future<void> scanFrom(String path) => browser.goTo(path);

  Future<void> scanUp() => browser.up();

  Future<void> rescan() => browser.rescan();

  Future<List<String>> drives() => browser.listDrives();

  /// Resolve the hints and walk from the start folder; the list fills in as the walk finds repos.
  Future<void> load() async {
    final gen = ++_loadGen;
    loading = true;
    notifyListeners();
    try {
      final resolved = await _hintsNow().resolve();
      if (gen != _loadGen || _disposed) return;
      hints = resolved;
      error = null;
    } catch (e) {
      error = '$e';
    }
    loading = false;
    cursor = cursor.clamp(0, (shown.length - 1).clamp(0, 1 << 30));
    notifyListeners();
    if (!_disposed) await browser.scan();
  }

  void setFilter(String q) {
    filter = q;
    cursor = 0;
    notifyListeners();
  }

  void move(int delta) {
    final n = shown.length;
    if (n == 0) return;
    cursor = (cursor + delta).clamp(0, n - 1);
    notifyListeners();
  }

  void toggleNewNeovim() {
    newNeovim = !newNeovim;
    notifyListeners();
  }

  /// Forget a stale hint (the folder is gone, or is no repository any more).
  void remove(String path) {
    session.prefs.forgetProject(path);
    hints = [for (final h in hints) if (h.path.toLowerCase() != path.toLowerCase()) h];
    browser.drop(path);
    notifyListeners();
  }

  /// Where the Active Directory opens (see [openTarget]); the tasks when git can't tell.
  Future<OpenTarget> openingTarget() async {
    final b = session.backend;
    if (b == null) return OpenTarget.tasks;
    try {
      return openTarget(await b.branches(), await b.status());
    } catch (_) {
      return OpenTarget.tasks;
    }
  }

  /// Make [dir] the Active Directory. Without a Neovim (a local session, or none yet) that opens
  /// the repository with the local backend; with one it is `:cd`, or a new Neovim there. Returns
  /// the error text, or null.
  Future<String?> pick(String dir) async {
    final b = session.backend;
    if (b == null || session.kind == BackendKind.local) return _openLocal(dir);
    if (!newNeovim) {
      String? cwd;
      final err = await session.run((b) async => cwd = await b.cd(dir));
      if (cwd != null && session.repo?.cwd != cwd) session.movedTo(cwd!);
      if (err == null) _remember(dir);
      return err;
    }
    try {
      final root = await b.pluginRoot();
      if (root == null) return 'cannot find the nvimos plugin to start a new Neovim with';
      final port = await freeLoopbackPort();
      final address = '127.0.0.1:$port';
      await launch(dir, address, root);
      // Drops the current connection; retries every 2 s until the new Neovim listens.
      await session.connect(address: address);
      _remember(dir);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> _openLocal(String dir) async {
    await session.openFolder(dir);
    if (session.conn != Conn.connected) {
      browser.drop(dir); // git refused it: stop offering it
      return session.error ?? 'cannot open $dir';
    }
    _remember(dir);
    return null;
  }

  void _remember(String dir) {
    session.prefs.rememberProject(dir);
    session.prefs.setLastProjectFolder(dir);
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_onSession);
    if (_started) browser.removeListener(notifyListeners);
    if (_browserOverride == null) browser.dispose();
    super.dispose();
  }
}

/// Start Neovim in a new console window, listening on [address], with the backend plugin added
/// after the user's config (which may reset the runtimepath), like `make nvim`.
Future<void> launchNeovim(String dir, String address, String pluginRoot) async {
  final nvim = ['nvim', '--listen', address, '-c', 'set rtp^=$pluginRoot', '-c', 'runtime plugin/nvimos.lua'];
  if (Platform.isWindows) {
    // `start ""` opens a new console; the empty first argument is the window title.
    await Process.start('cmd', ['/c', 'start', '', ...nvim], workingDirectory: dir, mode: ProcessStartMode.detached);
  } else {
    await Process.start(nvim.first, nvim.sublist(1), workingDirectory: dir, mode: ProcessStartMode.detached);
  }
}
