import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/backend.dart';
import 'package:nvimos_poc/rpc/client.dart';

import 'support/nvim.dart';

void main() {
  late Directory repo;
  late TestNvim nvim;
  late Backend b;

  setUp(() async {
    repo = await makeRepo();
    nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    b = await Backend.connect('127.0.0.1', nvim.port);
  });

  tearDown(() async {
    await b.close();
    await nvim.stop();
  });

  test('attach returns snapshots; events arrive in order', () async {
    final snaps = await b.attach(['buffers', 'windows', 'git']);
    expect(snaps['git']!['head'], 'main');
    expect(snaps['windows']!['current'], isA<Map>());
    final ev = b.events.firstWhere((e) => e.domain == 'buffers' && e.reason == 'lines_changed');
    await b.rpc.request('nvim_buf_set_lines', [0, 0, -1, false, ['x']]);
    expect((await ev.timeout(const Duration(seconds: 5))).data['lines'], ['x']);
  });

  test('a gap in seq triggers a resync snapshot; stale events are dropped', () async {
    await b.attach(['buffers']);
    final snap = b.events.firstWhere((e) => e.reason == 'snapshot');
    b.handleEvent({'domain': 'buffers', 'seq': 0, 'reason': 'stale'});
    b.handleEvent({'domain': 'buffers', 'seq': 99, 'reason': 'lines_changed'});
    final s = await snap.timeout(const Duration(seconds: 5));
    expect(s.data['buffers'], isA<List>());
  });

  test('git calls return typed data', () async {
    await git(repo, ['checkout', '-q', '-b', 'feature']);
    await File('${repo.path}/a.txt').writeAsString('one\nTWO\nthree\nfour\nfive\n');
    await git(repo, ['commit', '-q', '-am', 'edit']);
    await git(repo, ['checkout', '-q', 'main']);
    final br = await b.branches();
    expect(br.current, 'main');
    expect(br.list.map((x) => x.name), containsAll(['main', 'feature']));
    final log = await b.log('main', 'feature');
    expect(log.single.subject, 'edit');
    final d = await b.diff('main', 'feature');
    final f = d.files.single;
    expect([f.path, f.additions, f.deletions], ['a.txt', 1, 1]);
    expect(f.hunks.single.firstChangedLine, 2);
    await File('${repo.path}/b.txt').writeAsString('changed\n');
    final st = await b.status();
    expect(st.files.single.unstaged, isTrue);
    await b.stage('b.txt');
    expect((await b.status()).files.single.staged, isTrue);
    expect((await b.diffFile('b.txt', staged: true))!.additions, 1);
    expect(await b.diffFile('a.txt', staged: false), isNull);
  });

  test('backend errors surface as NvimError', () async {
    await expectLater(b.show('HEAD', 'missing.txt', 1), throwsA(isA<NvimError>()));
  });
}
