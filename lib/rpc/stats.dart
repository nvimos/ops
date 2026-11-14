import 'dart:collection';

import 'call_origin.dart';

/// One request to Neovim: what it was, who asked, and how it went.
class RpcCall {
  RpcCall(this.origin, this.sentAt);

  final CallOrigin origin;

  /// When it was sent, as time since the app started.
  final Duration sentAt;

  /// How long the answer took; null while it is still waiting.
  Duration? took;
  bool ok = true;
}

/// How the conversation with Neovim is going: how many requests were sent, how many wait for an
/// answer right now, how long answers take, and which requests were the slowest and where they
/// came from. [NvimRpc] feeds it; the debug bar's network monitor shows it. One for the whole app
/// run, across reconnects. Everything is in memory for this run only; nothing is written anywhere.
class RpcStats {
  RpcStats({Duration Function()? clock}) : _clock = clock ?? _wallClock;

  static final instance = RpcStats();

  static final _watch = Stopwatch()..start();
  static Duration _wallClock() => _watch.elapsed;

  final Duration Function() _clock;

  /// Time since the app started (for listing when a request was sent).
  Duration get now => _clock();

  /// Requests that were sent, and how many of them failed (an error answer or a closed connection).
  int total = 0, failed = 0;

  /// The most requests that were waiting for an answer at the same time.
  int peakInFlight = 0;

  /// How many durations are kept for the percentiles.
  static const keep = 200;

  /// How many of the slowest requests are kept.
  static const keepSlowest = 30;

  /// The window the rate is counted over.
  static const rateWindow = Duration(seconds: 5);

  final _inFlight = <int, RpcCall>{}; // key -> the request waiting
  final _recent = Queue<Duration>(); // durations of the last [keep] answers
  final _sent = Queue<Duration>(); // when the requests of the last [rateWindow] were sent
  final _slow = <RpcCall>[]; // the slowest answered requests, slowest first
  Duration _slowest = Duration.zero;

  /// Requests sent and not answered yet.
  int get inFlight => _inFlight.length;

  /// The requests that wait for an answer now, the longest-waiting first.
  List<RpcCall> get waiting => _inFlight.values.toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));

  /// The slowest answered requests of the run, slowest first (at most [keepSlowest]).
  List<RpcCall> get slowestCalls => List.unmodifiable(_slow);

  /// How long the oldest unanswered request has waited.
  Duration get oldestWait {
    if (_inFlight.isEmpty) return Duration.zero;
    return _clock() - waiting.first.sentAt;
  }

  /// The slowest answer of the run.
  Duration get slowest => _slowest;

  int _nextKey = 0;

  /// A request was sent; the returned key goes to [answered] (ids repeat across connections).
  int sent([CallOrigin origin = const CallOrigin(what: '', from: '', detail: '')]) {
    final key = _nextKey++;
    final at = _clock();
    total++;
    _inFlight[key] = RpcCall(origin, at);
    _sent.addLast(at);
    if (_inFlight.length > peakInFlight) peakInFlight = _inFlight.length;
    return key;
  }

  void answered(int key, {bool ok = true}) {
    final call = _inFlight.remove(key);
    if (!ok) failed++;
    if (call == null) return;
    final took = _clock() - call.sentAt;
    call
      ..took = took
      ..ok = ok;
    _recent.addLast(took);
    if (_recent.length > keep) _recent.removeFirst();
    if (took > _slowest) _slowest = took;
    _keepIfSlow(call);
  }

  void _keepIfSlow(RpcCall call) {
    if (_slow.length == keepSlowest && call.took! <= _slow.last.took!) return;
    _slow
      ..add(call)
      ..sort((a, b) => b.took!.compareTo(a.took!));
    if (_slow.length > keepSlowest) _slow.removeLast();
  }

  /// Requests per second over the last [rateWindow] (less while the run is younger than that).
  double get perSecond {
    final now = _clock();
    while (_sent.isNotEmpty && now - _sent.first > rateWindow) {
      _sent.removeFirst();
    }
    if (_sent.isEmpty) return 0;
    final span = now < rateWindow ? now : rateWindow;
    return _sent.length / (span.inMilliseconds / 1000).clamp(1, double.infinity);
  }

  /// The [p]th percentile (0 to 100, nearest rank) of the recent answer times; zero without any.
  Duration percentile(int p) {
    if (_recent.isEmpty) return Duration.zero;
    final sorted = _recent.toList()..sort();
    final rank = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  /// Back to zero (for tests).
  void reset() {
    total = failed = peakInFlight = 0;
    _inFlight.clear();
    _recent.clear();
    _sent.clear();
    _slow.clear();
    _slowest = Duration.zero;
  }
}
