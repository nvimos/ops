import 'dart:async';

import 'package:flutter/widgets.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import '../rpc/client.dart';

enum Conn { disconnected, connecting, connected }

/// The connection to Neovim and the live editor state every view shares.
class Session extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  Session({String host = '127.0.0.1', int port = 6666}) : _host = host, _port = port;

  String _host;
  int _port;
  Conn conn = Conn.disconnected;
  String? error;
  Backend? backend;
  Cursor? cursor;
  RepoInfo? repo;

  /// Bumps when git state may have changed (hint from the backend); views re-query.
  final gitChanged = ValueNotifier<int>(0);

  /// Paths named by the last git hints (planning files for the Tasks mode).
  final changedPaths = ValueNotifier<Set<String>>({});

  StreamSubscription<NvimEvent>? _sub;
  Timer? _retry;
  bool _disposed = false;

  String get address => '$_host:$_port';

  /// Connect now, and keep retrying every 2 s while not connected.
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
    _retry?.cancel();
    conn = Conn.connecting;
    _notify();
    try {
      final b = await Backend.connect(_host, _port);
      final snaps = await b.attach(['buffers', 'windows', 'git']);
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
      _scheduleRetry();
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

  void _scheduleRetry() {
    _retry?.cancel();
    if (_disposed) return;
    _retry = Timer(const Duration(seconds: 2), () => connect());
  }

  void _onEvent(NvimEvent ev) {
    switch (ev.domain) {
      case 'windows':
        final d = ev.reason == 'snapshot' ? asMap(ev.data['current']) : ev.data;
        if (ev.reason != 'win_closed') {
          cursor = Cursor(d);
          _notify();
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
    _scheduleRetry();
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

  /// Run a backend action; returns the error text for the UI, or null.
  Future<String?> run(Future<void> Function(Backend b) action) async {
    final b = backend;
    if (b == null) return 'not connected';
    try {
      await action(b);
      return null;
    } on NvimError catch (e) {
      return e.short;
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
    _retry?.cancel();
    _drop();
    gitChanged.dispose();
    changedPaths.dispose();
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
