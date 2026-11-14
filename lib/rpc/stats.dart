import 'dart:collection';

/// How the conversation with Neovim is going: how many requests were sent, how many wait for an
/// answer right now, how long answers take. [NvimRpc] feeds it; the debug bar's network monitor
/// shows it. One for the whole app run, across reconnects.
class RpcStats {
  RpcStats({Duration Function()? clock}) : _clock = clock ?? _wallClock;

  static final instance = RpcStats();

  static final _watch = Stopwatch()..start();
  static Duration _wallClock() => _watch.elapsed;

  final Duration Function() _clock;

  /// Requests that were sent, and how many of them failed (an error answer or a closed connection).
  int total = 0, failed = 0;

  /// The most requests that were waiting for an answer at the same time.
  int peakInFlight = 0;

  /// How many durations are kept for the percentiles.
  static const keep = 200;

  /// The window the rate is counted over.
  static const rateWindow = Duration(seconds: 5);

  final _inFlight = <int, Duration>{}; // request id -> when it was sent
  final _recent = Queue<Duration>(); // durations of the last [keep] answers
  final _sent = Queue<Duration>(); // when the requests of the last [rateWindow] were sent
  Duration _slowest = Duration.zero;

  /// Requests sent and not answered yet.
  int get inFlight => _inFlight.length;

  /// How long the oldest unanswered request has waited.
  Duration get oldestWait {
    if (_inFlight.isEmpty) return Duration.zero;
    final first = _inFlight.values.reduce((a, b) => a < b ? a : b);
    return _clock() - first;
  }

  /// The slowest answer of the run.
  Duration get slowest => _slowest;

  int _nextKey = 0;

  /// A request was sent; the returned key goes to [answered] (ids repeat across connections).
  int sent() {
    final id = _nextKey++;
    final now = _clock();
    total++;
    _inFlight[id] = now;
    _sent.addLast(now);
    if (_inFlight.length > peakInFlight) peakInFlight = _inFlight.length;
    return id;
  }

  void answered(int id, {bool ok = true}) {
    final at = _inFlight.remove(id);
    if (!ok) failed++;
    if (at == null) return;
    final took = _clock() - at;
    _recent.addLast(took);
    if (_recent.length > keep) _recent.removeFirst();
    if (took > _slowest) _slowest = took;
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
    _slowest = Duration.zero;
  }
}
