import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/terminals.dart';

import 'support/fake_system.dart';

/// A `where` that answers [paths] for the executables it holds.
Future<String?> Function(String) whichIn(Map<String, String> paths) =>
    (exe) async => paths[exe];

void main() {
  test('Windows Terminal leads when several terminals are found', () async {
    final launcher = TerminalLauncher(
      runner: FakeRunner(),
      which: whichIn({
        'cmd.exe': r'C:\Windows\System32\cmd.exe',
        'wt.exe': r'C:\Users\me\AppData\Local\Microsoft\WindowsApps\wt.exe',
        'pwsh.exe': r'C:\Program Files\PowerShell\7\pwsh.exe',
      }),
    );

    final found = await launcher.detect();

    expect(found.map((terminal) => terminal.id), ['wt', 'pwsh', 'cmd']);
    expect(TerminalLauncher.pick(found, null)?.id, 'wt');
    expect(TerminalLauncher.pick(found, 'pwsh')?.id, 'pwsh');
    // A saved terminal that is no longer installed falls back to the first.
    expect(TerminalLauncher.pick(found, 'gone')?.id, 'wt');
    expect(TerminalLauncher.pick(const [], null), isNull);
  });

  test('Windows Terminal opens its default profile in the folder', () async {
    final runner = FakeRunner();
    final launcher = TerminalLauncher(runner: runner, which: whichIn({'wt.exe': 'wt.exe'}));
    final terminal = (await launcher.detect()).single;

    await launcher.start(terminal, r'C:\work\repo');

    final call = runner.calls.single;
    expect(call.detached, isTrue);
    expect(call.exe, 'wt.exe');
    expect(call.args, ['-d', r'C:\work\repo']);
    expect(call.cwd, r'C:\work\repo');
  });

  test('a console shell opens through start, in the folder', () async {
    final runner = FakeRunner();
    final launcher = TerminalLauncher(
      runner: runner,
      which: whichIn({'cmd.exe': r'C:\Windows\System32\cmd.exe'}),
    );
    final terminal = (await launcher.detect()).single;

    await launcher.start(terminal, r'C:\work\repo');

    final call = runner.calls.single;
    expect(call.exe, 'cmd');
    expect(call.args, ['/c', 'start', '', r'C:\Windows\System32\cmd.exe']);
    expect(call.cwd, r'C:\work\repo');
  });
}
