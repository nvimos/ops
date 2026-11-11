import 'dart:async';

import 'package:flutter/widgets.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import '../rpc/client.dart';
import 'nvim_launcher.dart';

enum Conn { disconnected, connecting, connected }

/// The connection to Neovim and the live editor state every view shares.
class Session extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  Session({String host = '127.0.0.1', int port = 6666}) : _host = host, _port = port;

  String _host;
  int _port;
  Conn conn = Conn.disconnected;
  String? error;

  /// True while [startNeovim] launches Neovim and waits for it to listen.
  bool starting = false;
  Backend? backend;
  Cursor? cursor;
  RepoInfo? repo;

  /// Bumps when git state may have changed (hint from the backend); views re-query.
  final gitChanged = ValueNotifier<int>(0);

  /// Jobs started through the backend (agents), by id; updated from `jobs` events.
  final jobs = ValueNotifier<Map<int, Job>>({});

  /// Paths named by the last git hints (planning files for the Tasks mode).
  final changedPaths = ValueNotifier<Set<String>>({});

  StreamSubscription<NvimEvent>? _sub;
  bool _disposed = false;

  String get address => '$_host:$_port';

  /// Try to connect once; on failure [error] says why and the user retries.
  Future<void> connect({String? address}) async {
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
    _notify();
    try {
      final b = await Backend.connect(_host, _port);
      final snaps = await b.attach(['buffers', 'windows', 'git', 'jobs']);
      backend = b;
      conn = Conn.connected;
      error = null;
      cursor = Cursor(asMap(snaps['windows']?['current']));
      repo = RepoInfo(snaps['git'] ?? const {});
      _sub = b.events.listen(_onEvent);
      b.done.then((_) => _lost());
      gitChanged.value++;
    } catch (e) {
      conn = Conn.disconnected;
      error = e is NvimError ? e.short : _shortError(e);
    }
    _notify();
  }

  String _shortError(Object e) {
    final s = '$e';
    if (s.contains('refused') || s.contains('errno = 10061') || s.contains('SocketException')) {
      return 'no Neovim listening on $address';
    }
    return s;
  }

  /// Start Neovim on [address] with the backend plugin, then connect once it listens
  /// (up to about 10 s).
  Future<void> startNeovim() async {
    if (conn != Conn.disconnected || starting) return;
    starting = true;
    error = null;
    _notify();
    final failed = await launchNeovim(address);
    if (failed != null) error = failed;
    for (var i = 0; failed == null && i < 20 && conn != Conn.connected && !_disposed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await connect();
    }
    starting = false;
    _notify();
  }

  void _onEvent(NvimEvent ev) {
    switch (ev.domain) {
      case 'windows':
        final d = ev.reason == 'snapshot' ? asMap(ev.data['current']) : ev.data;
        if (ev.reason != 'win_closed') {
          cursor = Cursor(d);
          _notify();
        }
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

  Future<void> _lost() async {
    if (backend == null) return;
    await _drop();
    error = 'Neovim went away';
    _notify();
  }

  Future<void> _drop() async {
    await _sub?.cancel();
    _sub = null;
    final b = backend;
    backend = null;
    conn = Conn.disconnected;
    cursor = null;
    if (b != null) await b.close();
  }

  /// The cwd moved without a repo change (no git event for that): keep [repo] current.
  void movedTo(String cwd) {
    repo = RepoInfo({'cwd': cwd, 'root': repo?.root, 'head': repo?.head});
    _notify();
  }

  /// Run a backend action; returns the full error text (with Neovim's trace), or null.
  /// The UI shows `shortError` of it and the full text on demand.
  Future<String?> run(Future<void> Function(Backend b) action) async {
    final b = backend;
    if (b == null) return 'not connected';
    try {
      await action(b);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _drop();
    gitChanged.dispose();
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
