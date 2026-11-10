import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/rpc/client.dart';

import 'support/nvim.dart';

void main() {
  late TestNvim nvim;
  late NvimRpc rpc;

  setUp(() async {
    nvim = await TestNvim.start();
    rpc = await nvim.connect();
  });

  tearDown(() async {
    await rpc.close();
    await nvim.stop();
  });

  test('request and response', () async {
    expect(await rpc.request('nvim_eval', ['1 + 1']), 2);
    final info = await rpc.request('nvim_get_api_info') as List;
    expect(info[0], isA<int>());
  });

  test('errors come back as NvimError with a short message', () async {
    final f = rpc.lua("error('nvimos: boom', 0)");
    await expectLater(f, throwsA(isA<NvimError>().having((e) => e.short, 'short', 'boom')));
  });

  test('buffer handles arrive as ints and work as arguments', () async {
    final buf = await rpc.request('nvim_get_current_buf');
    expect(buf, isA<int>());
    await rpc.request('nvim_buf_set_lines', [
      buf,
      0,
      -1,
      false,
      ['x', 'y'],
    ]);
    expect(await rpc.request('nvim_buf_get_lines', [buf, 0, -1, false]), ['x', 'y']);
  });

  test('the backend plugin sends nvimos notifications', () async {
    final info = await rpc.request('nvim_get_api_info') as List;
    await rpc.lua("return require('nvimos').attach(...)", [
      {
        'chan': info[0],
        'domains': ['buffers'],
      },
    ]);
    final ev = rpc.notifications.firstWhere((n) => n.method == 'nvimos');
    await rpc.request('nvim_buf_set_lines', [
      0,
      0,
      -1,
      false,
      ['hello'],
    ]);
    final n = await ev.timeout(const Duration(seconds: 5));
    final m = n.args[0] as Map;
    expect(m['domain'], 'buffers');
    expect(m['v'], 1);
  });

  test('done completes when Neovim exits', () async {
    rpc.notify('nvim_command', ['qa!']);
    await rpc.done.timeout(const Duration(seconds: 5));
    expect(rpc.isClosed, isTrue);
  });
}
