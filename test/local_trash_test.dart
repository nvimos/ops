import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/system.dart';
import 'package:nvimos_poc/local/trash.dart';

import 'support/fake_system.dart';

void main() {
  group('Trash', () {
    test('Windows asks the shell, with backslash paths, to recycle', () async {
      final shell = FakeShell();
      await Trash(env: const Env({}), shell: shell.call).send(['C:/r/a b.txt', 'C:/r/dir']);
      expect(shell.calls.single.paths, [r'C:\r\a b.txt', r'C:\r\dir']);
      expect(shell.calls.single.recycle, isTrue);
    });

    test('permanent on Windows is a delete without the Recycle Bin', () async {
      final shell = FakeShell();
      await Trash(env: const Env({}), shell: shell.call).send(['C:/r/a'], permanent: true);
      expect(shell.calls.single.recycle, isFalse);
    });

    test('a refusal from the shell says why in words', () async {
      final shell = FakeShell(0x7C);
      await expectLater(
        Trash(env: const Env({}), shell: shell.call).send(['C:/r/a']),
        throwsA(isA<TrashException>().having((e) => '$e', 'message', contains('in use by another program'))),
      );
    });

    test('macOS asks Finder', () {
      final mac = Trash(env: const Env({}, isWindows: false, isMacOS: true)).commands(['/r/a "x".txt']).single;
      expect(mac.$1, 'osascript');
      expect(mac.$2.last, r'tell application "Finder" to delete {POSIX file "/r/a \"x\".txt"}');
    });

    test('Linux tries gio, then trash-put, then rm; permanent is rm alone', () {
      final linux = Trash(env: const Env({}, isWindows: false));
      expect(linux.commands(['/r/a']).map((c) => c.$1), ['gio', 'trash-put', 'rm']);
      final permanent = linux.commands(['/r/a'], permanent: true).single;
      expect(permanent.$1, 'rm');
      expect(permanent.$2, ['-r', '--', '/r/a']);
    });

    test('a missing trash tool falls through, a failing one does not', () async {
      const linux = Env({}, isWindows: false);
      final missing = FakeRunner((call) => call.exe == 'rm' ? const ProcessOutput(0) : null);
      await Trash(runner: missing, env: linux).send(['/r/a']);
      expect(missing.calls.map((c) => c.exe), ['gio', 'trash-put', 'rm']);

      final refused = FakeRunner((call) => const ProcessOutput(1, stderr: 'cannot trash'));
      await expectLater(Trash(runner: refused, env: linux).send(['/r/a']), throwsA(isA<TrashException>()));
      expect(refused.calls.map((c) => c.exe), ['gio']);
    });
  });
}
