import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/session.dart';

import 'session_test.dart' show until;
import 'support/nvim.dart';

void main() {
  test('lists changes, stages a hunk, commits, follows edits made in Neovim', () async {
    final repo = await makeRepo();
    final lines = List.generate(12, (i) => 'line ${i + 1}');
    await File('${repo.path}/a.txt').writeAsString('${lines.join('\n')}\n');
    await git(repo, ['commit', '-q', '-am', 'twelve']);
    lines[0] = 'LINE 1';
    lines[9] = 'LINE 10';
    await File('${repo.path}/a.txt').writeAsString('${lines.join('\n')}\n');

    final nvim = await TestNvim.start(cwd: repo);
    await nvim.connect().then((r) => r.close());
    final s = Session(port: nvim.port);
    await s.connect();
    final st = ChangesState(s);
    await until(() => st.diff != null);
    expect(st.selected, 'a.txt');
    expect(st.diff!.hunks.length, 2);

    expect(await st.act((b) => b.stageHunk('a.txt', st.diff!.hunks.first)), isNull);
    await until(() => st.staged.length == 1 && st.unstaged.length == 1);

    expect(await st.commit('first hunk'), isNull);
    await until(() => st.staged.isEmpty);
    expect((await git(repo, ['log', '-1', '--format=%s'])).trim(), 'first hunk');

    // Save a new file from Neovim: the list picks it up from the write hint.
    await s.backend!.rpc.request('nvim_command', ['edit new.txt']);
    await s.backend!.rpc.request('nvim_buf_set_lines', [0, 0, -1, false, ['hello']]);
    await s.backend!.rpc.request('nvim_command', ['write']);
    await until(() => st.unstaged.any((f) => f.path == 'new.txt'));

    st.dispose();
    s.dispose();
    await nvim.stop();
  });
}
