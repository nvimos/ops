/// Hot reload and hot restart from inside the running app.
///
/// `flutter run` (so `make run` and `make live`) registers both as services on
/// the Dart VM service; this connects to the app's own VM service, finds them
/// and calls them, which is what an IDE does. A release build has no VM service
/// and no `flutter run`, so [available] is false there and the buttons are not
/// drawn. All Dart: `dart:developer` for the address, a `dart:io` WebSocket for
/// the JSON-RPC.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kDebugMode;

/// Why a reload or restart did not happen, in one line.
class HotException implements Exception {
  HotException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The two actions; tests and release builds use a subclass or [available].
class HotReload {
  const HotReload();

  /// Only a debug run has a VM service for `flutter run` to be attached to.
  bool get available => kDebugMode;

  /// Reload the changed code and keep the state.
  Future<void> reload() => _call('reloadSources', waitForAnswer: true);

  /// Start the app again from `main`. The answer never comes: the app that
  /// asked is the one being replaced.
  Future<void> restart() => _call('hotRestart', waitForAnswer: false);

  Future<void> _call(String service, {required bool waitForAnswer}) async {
    if (!available) throw HotException('hot reload exists only in a debug run (make run, make live)');
    final address = (await developer.Service.getInfo()).serverWebSocketUri;
    if (address == null) throw HotException('the VM service is not running');
    final session = await _Session.open(address);
    try {
      final method = await session.methodOf(service);
      final isolate = developer.Service.getIsolateId(Isolate.current);
      final answer = session.call(method, {'isolateId': ?isolate});
      if (!waitForAnswer) {
        await answer.timeout(const Duration(seconds: 2), onTimeout: () => const {});
        return;
      }
      final result = await answer.timeout(const Duration(seconds: 30));
      if (result['success'] == false) throw HotException('the reload was refused: see the `flutter run` output');
    } on TimeoutException {
      throw HotException('flutter run did not answer');
    } on WebSocketException catch (error) {
      // A restart ends the connection from the other side; that is the answer.
      if (waitForAnswer) throw HotException('lost the VM service: ${error.message}');
    } finally {
      await session.close();
    }
  }
}

/// One JSON-RPC conversation with the VM service.
class _Session {
  _Session._(this._socket) {
    _socket.listen(_onMessage, onDone: _onDone);
  }

  static Future<_Session> open(Uri address) async =>
      _Session._(await WebSocket.connect(address.toString()).timeout(const Duration(seconds: 5)));

  final WebSocket _socket;
  final Map<int, Completer<Map<String, Object?>>> _waiting = {};
  final Map<String, String> _services = {};
  final Map<String, Completer<String>> _wanted = {};
  int _next = 0;

  void _onMessage(Object? raw) {
    final message = jsonDecode(raw as String) as Map<String, Object?>;
    final id = message['id'];
    if (id is int) {
      final waiting = _waiting.remove(id);
      if (waiting == null) return;
      final error = message['error'];
      if (error is Map) {
        waiting.completeError(HotException('${error['message']}'));
      } else {
        waiting.complete((message['result'] as Map?)?.cast<String, Object?>() ?? const {});
      }
      return;
    }
    if (message['method'] != 'streamNotify') return;
    final event = (message['params'] as Map?)?['event'];
    if (event is! Map || event['kind'] != 'ServiceRegistered') return;
    final service = '${event['service']}';
    final method = '${event['method']}';
    _services[service] = method;
    _wanted.remove(service)?.complete(method);
  }

  void _onDone() {
    for (final waiting in _waiting.values) {
      if (!waiting.isCompleted) waiting.complete(const {});
    }
    _waiting.clear();
  }

  Future<Map<String, Object?>> call(String method, Map<String, Object?> params) {
    final id = _next++;
    final waiting = _waiting[id] = Completer<Map<String, Object?>>();
    _socket.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return waiting.future;
  }

  /// The method name `flutter run` registered [service] under (`s0.hotRestart`).
  /// Listening to the Service stream replays the registrations made so far.
  Future<String> methodOf(String service) async {
    final wanted = _wanted[service] = Completer<String>();
    await call('streamListen', {'streamId': 'Service'});
    final known = _services[service];
    if (known != null) return known;
    return wanted.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw HotException('this app was not started by `flutter run`: no $service service'),
    );
  }

  Future<void> close() => _socket.close();
}
