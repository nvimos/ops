import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/rpc/call_origin.dart';
import 'package:nvimos_poc/rpc/stats.dart';
import 'package:nvimos_poc/ui/debug_bar.dart';
import 'package:nvimos_poc/ui/theme.dart';

const _trace = '''
#0      NvimRpc.request (package:nvimos_poc/rpc/client.dart:68:5)
#1      NvimRpc.lua (package:nvimos_poc/rpc/client.dart:77:9)
#2      Backend._lua.<anonymous closure> (package:nvimos_poc/backend/backend.dart:78:62)
#3      UiTiming.time (package:nvimos_poc/timing/ui_timing.dart:90:12)
#4      Backend.diffFile (package:nvimos_poc/backend/backend.dart:145:5)
#5      ChangesState._loadDiff (package:nvimos_poc/state/changes.dart:140:20)
#6      ChangesState._loadDiffSoon.<anonymous closure> (package:nvimos_poc/state/changes.dart:131:5)
#7      _ChangesViewState._pick (package:nvimos_poc/ui/changes_view.dart:210:9)
#8      _rootRunUnary (dart:async/zone.dart:1407:47)
''';

void main() {
  test('a request is named by its Lua function and traced to the app functions that asked', () {
    final o = describeRequest(
      'nvim_exec_lua',
      ["return require('nvimos.git').diff_file(...)", ['src/a.dart', true]],
      StackTrace.fromString(_trace),
    );
    expect(o.what, 'nvimos.git.diff_file');
    expect(o.detail, 'src/a.dart');
    // the client, the backend wrapper and the timing helper are skipped; closures lose their suffix
    expect(o.from, 'ChangesState._loadDiff ← ChangesState._loadDiffSoon ← _ChangesViewState._pick');

    final plain = describeRequest('nvim_get_api_info', const [], StackTrace.fromString(_trace));
    expect(plain.what, 'nvim_get_api_info');
    expect(plain.detail, '');
  });

  test('the slowest requests are kept, slowest first, and the waiting ones are listed', () {
    var now = Duration.zero;
    final s = RpcStats(clock: () => now);
    CallOrigin of(String what) => CallOrigin(what: what, from: 'X.y', detail: '');
    final fast = s.sent(of('fast')), slow = s.sent(of('slow')), stuck = s.sent(of('stuck'));
    now = const Duration(milliseconds: 20);
    s.answered(fast);
    now = const Duration(milliseconds: 900);
    s.answered(slow);
    expect([for (final c in s.slowestCalls) c.origin.what], ['slow', 'fast']);
    expect(s.slowestCalls.first.took, const Duration(milliseconds: 900));
    expect([for (final c in s.waiting) c.origin.what], ['stuck']);
    now = const Duration(milliseconds: 1200);
    s.answered(stuck, ok: false);
    expect(s.slowestCalls.first.origin.what, 'stuck');
    expect(s.slowestCalls.first.ok, false);

    for (var i = 0; i < 40; i++) {
      final k = s.sent(of('r$i'));
      now += const Duration(seconds: 1);
      s.answered(k);
    }
    expect(s.slowestCalls.length, RpcStats.keepSlowest);
  });

  testWidgets('a click on the network monitor opens the list of the slowest requests', (t) async {
    final stats = RpcStats.instance..reset();
    final k = stats.sent(const CallOrigin(what: 'nvimos.git.status', from: 'ChangesState._refresh', detail: ''));
    stats.answered(k);
    addTearDown(stats.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: Center(child: NetworkMonitor()))));
    await t.tap(find.byType(NetworkMonitor));
    await t.pumpAndSettle();
    expect(find.text('Requests to Neovim'), findsOneWidget);
    expect(find.textContaining('nvimos.git.status'), findsOneWidget);
    expect(find.textContaining('ChangesState._refresh'), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(find.text('Requests to Neovim'), findsNothing);
    await t.pumpWidget(const SizedBox()); // the monitor's timer is gone with it
  });
}
