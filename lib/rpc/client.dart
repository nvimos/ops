import 'dart:async';
import 'dart:io';

import 'msgpack.dart';

/// An error Neovim returned for a request.
class NvimError implements Exception {
  NvimError(this.method, this.message);
  final String method;
  final String message;

  /// The message without Neovim's "Lua: ..." / "Vim:..." prefixes and stack traces, for the UI.
  String get short {
    var m = message.split('\nstack traceback')[0].trim();
    m = m.replaceFirst(RegExp(r'^(Lua|Vim):\s*'), '');
    final i = m.indexOf('nvimos: ');
    return i >= 0 ? m.substring(i + 8) : m;
  }

  @override
  String toString() => 'NvimError($method): $message';
}

class RpcNotification {
  RpcNotification(this.method, this.args);
  final String method;
  final List<Object?> args;
}

/// msgpack-RPC over TCP to Neovim.
class NvimRpc {
  NvimRpc._(this._socket) {
    _socket.listen(_onData, onDone: _onDone, onError: (Object _) => _onDone(), cancelOnError: true);
  }

  final Socket _socket;
  final _decoder = MsgDecoder();
  final _pending = <int, Completer<Object?>>{};
  final _notes = StreamController<RpcNotification>.broadcast();
  final _done = Completer<void>();
  int _nextId = 1;
  bool _closed = false;

  static Future<NvimRpc> connect(String host, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    final s = await Socket.connect(host, port, timeout: timeout);
    s.setOption(SocketOption.tcpNoDelay, true);
    return NvimRpc._(s);
  }

  Stream<RpcNotification> get notifications => _notes.stream;

  /// Completes when the connection closes (either side).
  Future<void> get done => _done.future;

  bool get isClosed => _closed;

  Future<Object?> request(String method, [List<Object?> args = const []]) {
    if (_closed) return Future.error(StateError('not connected'));
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _socket.add(msgEncode([0, id, method, args]));
    return c.future;
  }

  void notify(String method, [List<Object?> args = const []]) {
    if (_closed) return;
    _socket.add(msgEncode([2, method, args]));
  }

  /// Run Lua in Neovim; `...` in the code are `args`.
  Future<Object?> lua(String code, [List<Object?> args = const []]) => request('nvim_exec_lua', [code, args]);

  void _onData(List<int> chunk) {
    for (final msg in _decoder.add(chunk)) {
      if (msg is! List || msg.isEmpty) continue;
      switch (msg[0]) {
        case 1:
          final c = _pending.remove(msg[1]);
          if (c == null) break;
          final err = msg[2];
          if (err != null) {
            final text = err is List && err.length > 1 ? '${err[1]}' : '$err';
            c.completeError(NvimError('${msg[1]}', text));
          } else {
            c.complete(msg[3]);
          }
          break;
        case 2:
          _notes.add(RpcNotification('${msg[1]}', (msg[2] as List?)?.cast<Object?>() ?? const []));
          break;
        case 0:
          _socket.add(msgEncode([1, msg[1], 'requests are not supported', null]));
          break;
      }
    }
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(StateError('connection closed'));
    }
    _pending.clear();
    _notes.close();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> close() async {
    if (_closed) return;
    await _socket.close();
    _socket.destroy();
    _onDone();
  }
}
