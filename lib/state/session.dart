import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import '../backend/repo_backend.dart';
import '../local/local_backend.dart';
import '../rpc/client.dart';
import 'action_queue.dart';
import 'diff_prefs.dart';
import 'merge_conflict.dart';
import 'nvim_launcher.dart';
import 'prefs.dart';
import 'status_store.dart';

export 'diff_prefs.dart';

enum Conn { disconnected, connecting, connected }

/// The connection to Neovim and the live editor state every view shares.
class Session extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  /// [prefs]: where view choices are kept; the app passes the state file's (`Prefs.load()`), tests
  /// keep them in memory.
  Session({this._host = '127.0.0.1', this._port = 6666, Prefs? prefs}) : _prefs = prefs ?? Prefs.memory();

  final Prefs _prefs;

  /// The user's small settings (recent folders, view choices).
  Prefs get prefs => _prefs;

  String _host;
  int _port;
  Conn conn = Conn.disconnected;
  String? error;

  /// What [startNeovim] is launching while it waits for Neovim to listen.
  NvimKind? starting;

  /// A short outcome that is not an error (e.g. how many headless Neovims were stopped).
  String? notice;

  /// A directory was named on the command line: once connected, show its opening mode
  /// (the same choice the Directories mode makes, see `openTarget`).
  bool openProjectOnConnect = false;
  RepoBackend? backend;

  /// The editor behind the backend; null when there is none (modes hide `open` / `show` then).
  EditorSession? editor;

  /// There is an editor to open files in; the controls that need one are not drawn without it.
  bool get hasEditor => editor != null;
  Cursor? cursor;
  RepoInfo? repo;

  /// Unified / side-by-side, wrapping and hunk headers, shared by the diff modes.
  late final diffPrefs = DiffPrefs(_prefs);

  /// The merges with conflicts: the open one is shown in Changes and Pull request alike.
  late final conflicts = ConflictController(run, diffPrefs);

  /// The repository's status, shared by the modes that list files; made when first used.
  StatusStore get store => _store ??= StatusStore(this);
  StatusStore? _store;

  /// The actions on that status, one at a time.
  ActionQueue get actions => _actions ??= ActionQueue(this, store);
  ActionQueue? _actions;

  /// Bumps when git state may have changed (hint from the backend); views re-query.
  final gitChanged = ValueNotifier<int>(0);

  /// Jobs started through the backend (agents), by id; updated from `jobs` events.
  final jobs = ValueNotifier<Map<int, Job>>({});

  /// Paths named by the last git hints (planning files for the Tasks mode).
  final changedPaths = ValueNotifier<Set<String>>({});

  StreamSubscription<NvimEvent>? _sub;
  StreamSubscription<Cursor>? _cursorSub;
  bool _disposed = false;

  String get address => '$_host:$_port';

  /// Try to connect once; on failure [error] says why and the user retries.
  Future<void> connect({String? address, Duration? timeout}) async {
    final limit = timeout ?? connectTimeout;
    if (address != null) {
      final i = address.lastIndexOf(':');
      if (i > 0) {
        _host = address.substring(0, i);
        _port = int.tryParse(address.substring(i + 1)) ?? _port;
      }
      await _drop();
    }
    if (conn != Conn.disconnected) return;
    conn = Conn.connecting;
    final mine = ++_attempt;
    _notify();
    NvimBackend? b;
    try {
      b = await NvimBackend.connect(_host, _port, timeout: limit);
      final snaps = await b.attach(['buffers', 'windows', 'git', 'jobs']).timeout(limit);
      if (mine != _attempt) return await b.close(); // cancelled meanwhile; the state is already reset
      backend = b;
      editor = b;
      conn = Conn.connected;
      error = null;
      cursor = Cursor(asMap(snaps['windows']?['current']));
      repo = RepoInfo(snaps['git'] ?? const {});
      _sub = b.events.listen(_onEvent);
      _cursorSub = b.cursors.listen(_onCursor);
      b.done.then((_) => _lost());
      kind = BackendKind.nvim;
      epoch++;
      _prefs.addRecent(Recent(BackendKind.nvim, this.address));
      gitChanged.value++;
    } catch (e) {
      b?.close();
      if (mine != _attempt) return;
      conn = Conn.disconnected;
      error = e is TimeoutException ? 'no answer from $_host:$_port within ${limit.inSeconds} s' : (e is NvimError ? e.short : _shortError(e));
    }
    _notify();
  }

  /// Open the repository in [dir] with the local backend: no Neovim, no editor. The repository
  /// watcher raises the git hints. On failure [error] says why. [openProject]: show the opening
  /// mode once connected (a folder named on the command line).
  Future<void> openFolder(String dir, {bool openProject = false}) async {
    await _drop();
    conn = Conn.connecting;
    error = notice = null;
    final mine = ++_attempt;
    _notify();
    LocalBackend? b;
    try {
      b = await LocalBackend.open(dir);
      final branches = await b.branches();
      if (mine != _attempt) return await b.close();
      backend = b;
      editor = null;
      conn = Conn.connected;
      cursor = null;
      repo = RepoInfo({'cwd': b.root, 'root': b.root, 'head': branches.current});
      _sub = b.events.listen(_onEvent);
      b.done.then((_) => _lost());
      b.watch();
      kind = BackendKind.local;
      epoch++;
      openProjectOnConnect = openProject;
      _prefs.addRecent(Recent(BackendKind.local, b.root));
      gitChanged.value++;
    } catch (e) {
      b?.close();
      if (mine != _attempt) return;
      conn = Conn.disconnected;
      error = 'cannot open $dir: ${e is NvimError ? e.short : _shortError(e)}';
    }
    _notify();
  }

  /// Open a remembered entry with the backend it remembers.
  Future<void> openRecent(Recent r) => switch (r.kind) {
    BackendKind.local => openFolder(r.target),
    BackendKind.nvim => connect(address: r.target),
  };

  /// The folders and addresses opened before, newest first.
  List<Recent> get recents => _prefs.recents();

  /// Drop [r] from the recent list.
  void forget(Recent r) {
    _prefs.removeRecent(r);
    _notify();
  }

  /// Which backend the open connection uses.
  BackendKind kind = BackendKind.nvim;

  /// Bumps whenever the backend changes or goes away: what a mode built for the old one is stale.
  int epoch = 0;

  /// How long a connection attempt may take before it counts as failed.
  Duration connectTimeout = const Duration(seconds: 8);

  /// Bumps per attempt and per cancel: an attempt that finds it changed was cancelled.
  int _attempt = 0;
  int _startToken = 0;

  /// Give up on the running connection attempt (and on a Neovim start waiting to connect).
  void cancelConnect() {
    if (conn != Conn.connecting && starting == null) return;
    _attempt++;
    _startToken++;
    if (conn == Conn.connecting) conn = Conn.disconnected;
    starting = null;
    error = null;
    notice = 'connecting cancelled';
    _notify();
  }

  String _shortError(Object e) {
    final s = '$e';
    if (s.contains('refused') || s.contains('errno = 10061') || s.contains('SocketException')) {
      return 'no Neovim listening on $address';
    }
    return s;
  }

  /// Start Neovim on [address] with the backend plugin (in a console, nvim-qt or headless), then
  /// connect once it listens (up to about 12 s). Whatever goes wrong ends in [error], never in a
  /// button stuck on "Starting…".
  /// With [dir] the Neovim opens that directory, on a free loopback port instead of the current
  /// address (so it does not collide with a Neovim already running).
  Future<void> startNeovim({NvimKind kind = NvimKind.console, String? dir}) async {
    if (conn != Conn.disconnected || starting != null) return;
    starting = kind;
    final token = ++_startToken;
    error = notice = null;
    launchLog = '';
    if (dir != null) openProjectOnConnect = true;
    _notify();
    try {
      if (dir != null) {
        _host = '127.0.0.1';
        _port = await freeLoopbackPort();
        if (token != _startToken) return;
      }
      final failed = await _startAndConnect(kind, token, dir);
      if (token == _startToken && failed != null) error = failed;
    } catch (e) {
      if (token == _startToken) error = 'could not start ${kind.label}: $e';
    } finally {
      if (token == _startToken) {
        starting = null;
        _notify();
      }
    }
  }

  /// The failure text, or null when connected (or cancelled).
  Future<String?> _startAndConnect(NvimKind kind, int token, String? dir) async {
    _logLine('> ${kind.label} on $address');
    if (await _taken()) {
      final text = '$address is taken by a program that does not answer as Neovim with the nvimos plugin; '
          'close it or use another address';
      _logLine('! $text');
      return text;
    }
    final failed = await launchNeovim(address, kind: kind, dir: dir, log: _logLine);
    if (failed != null) {
      _logLine('! $failed');
      return failed;
    }
    _logLine('waiting for Neovim to listen on $address (up to 12 s)');
    final end = DateTime.now().add(const Duration(seconds: 12));
    while (token == _startToken && conn != Conn.connected && !_disposed) {
      if (DateTime.now().isAfter(end)) {
        final text = error ?? 'Neovim did not listen on $address within 12 s';
        _logLine('! $text');
        return text;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (token == _startToken) await connect(timeout: const Duration(seconds: 3));
    }
    if (conn == Conn.connected) _logLine('connected to $address');
    return null;
  }

  /// What the last start did, as text (the commands, their output, why it failed): shown on the
  /// connect screen, selectable.
  String launchLog = '';

  void _logLine(String line) {
    launchLog = launchLog.isEmpty ? line : '$launchLog\n$line';
    _notify();
  }

  /// Something already accepts connections on [address] (and, as we are disconnected, did not
  /// work as a Neovim with the plugin): a second Neovim could not listen there.
  Future<bool> _taken() async {
    try {
      final s = await Socket.connect(_host, _port, timeout: const Duration(seconds: 1));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stop every headless Neovim of this user, connected or not.
  Future<void> stopHeadlessNeovims() async {
    error = notice = null;
    try {
      final (n, failed) = await stopHeadless();
      error = failed;
      notice = failed == null ? (n == 0 ? 'no headless Neovim running' : 'stopped $n headless Neovim') : null;
    } catch (e) {
      error = 'could not stop headless Neovim: $e';
    }
    _notify();
  }

  void _onEvent(NvimEvent ev) {
    switch (ev.domain) {
      case 'jobs':
        if (ev.reason != 'snapshot') {
          final j = Job(ev.data);
          jobs.value = {...jobs.value, j.id: j};
        }
      case 'git':
        repo = RepoInfo(ev.data);
        changedPaths.value = asList(ev.data['paths']).map(str).toSet();
        gitChanged.value++;
        _notify();
    }
  }

  void _onCursor(Cursor c) {
    cursor = c;
    _notify();
  }

  Future<void> _lost() async {
    if (backend == null) return;
    await _drop();
    error = kind == BackendKind.nvim ? 'Neovim went away' : 'the repository went away';
    _notify();
  }

  Future<void> _drop() async {
    await _sub?.cancel();
    _sub = null;
    await _cursorSub?.cancel();
    _cursorSub = null;
    final b = backend;
    backend = null;
    editor = null;
    conn = Conn.disconnected;
    cursor = null;
    if (b != null) {
      epoch++;
      if (!_disposed) {
        _store?.reset();
        jobs.value = {};
        changedPaths.value = {};
      }
    }
    if (b != null) await b.close();
  }

  /// Close the connection (and stop the repository watcher of a local one); resolves when the
  /// backend is closed, so a test can delete its folder after it.
  Future<void> disconnect() async {
    await _drop();
    _notify();
  }

  /// The cwd moved without a repo change (no git event for that): keep [repo] current.
  void movedTo(String cwd) {
    repo = RepoInfo({'cwd': cwd, 'root': repo?.root, 'head': repo?.head});
    _notify();
  }

  /// Run a backend action; returns the full error text (with Neovim's trace), or null.
  /// The UI shows `shortError` of it and the full text on demand.
  Future<String?> run(Future<void> Function(RepoBackend b) action) async {
    final b = backend;
    if (b == null) return 'not connected';
    return _guard(() => action(b));
  }

  /// Run an editor action (open, show); 'no editor' when this session has none.
  Future<String?> runEditor(Future<void> Function(EditorSession e) action) async {
    final e = editor;
    if (e == null) return backend == null ? 'not connected' : 'no editor';
    return _guard(() => action(e));
  }

  Future<String?> _guard(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Show [text] as the connect screen's error (for failures the UI catches itself).
  void showError(String text) {
    error = text;
    notice = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _drop();
    _store?.dispose();
    gitChanged.dispose();
    diffPrefs.dispose();
    changedPaths.dispose();
    jobs.dispose();
    super.dispose();
  }
}

/// Makes the Session available below it; widgets rebuild when it notifies.
class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child}) : super(notifier: session);

  static Session of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// Without subscribing to rebuilds.
  static Session read(BuildContext context) => context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
