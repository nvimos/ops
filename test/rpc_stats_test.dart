import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/rpc/stats.dart';
import 'package:nvimos_poc/ui/debug_bar.dart';

void main() {
  test('counts requests, the queue, answer times and the rate', () {
    var now = Duration.zero;
    final s = RpcStats(clock: () => now);
    final keys = [for (var i = 0; i < 10; i++) s.sent()];
    expect((s.total, s.inFlight, s.peakInFlight), (10, 10, 10));

    now = const Duration(milliseconds: 600);
    expect(s.oldestWait, const Duration(milliseconds: 600));
    for (final (i, k) in keys.indexed) {
      now = Duration(milliseconds: 600 + (i + 1) * 10); // answers take 610, 620 ... 700 ms
      s.answered(k, ok: i != 3);
    }
    expect((s.inFlight, s.failed, s.peakInFlight), (0, 1, 10));
    expect(s.percentile(50), const Duration(milliseconds: 650));
    expect(s.percentile(95), const Duration(milliseconds: 700));
    expect(s.slowest, const Duration(milliseconds: 700));

    now = const Duration(seconds: 2);
    expect(s.perSecond, 5); // 10 requests in the 2 seconds of the run
    now = const Duration(seconds: 30);
    expect(s.perSecond, 0); // none within the last 5 seconds
  });

  test('the monitor lines show a queue as a problem', () {
    var now = Duration.zero;
    final s = RpcStats(clock: () => now);
    expect(networkLines(s).join('|'), isNot(contains('!')));
    for (var i = 0; i < 8; i++) {
      s.sent();
    }
    now = const Duration(milliseconds: 50);
    final lines = networkLines(s);
    expect(lines[0], startsWith('Requests: 8 sent'));
    expect(lines[1], 'Waiting: 8 now, peak 8, oldest 50 ms!'); // more than 5 waiting: marked
    expect(lines[2], startsWith('Answers: p50 0 ms'));
  });
}
