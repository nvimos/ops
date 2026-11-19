/// Delete files the way the desktop does: into the Recycle Bin on Windows (the
/// shell's own call, from Dart through FFI), the Trash on macOS (Finder), and the
/// FreeDesktop trash on Linux (`gio`, `trash-put`), else `rm -r`.
library;

import 'dart:io';

import 'shell_delete.dart';
import 'system.dart';

/// A delete that did not happen, with the reason in one line.
class TrashException implements Exception {
  TrashException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the Windows shell is asked: delete [paths], into the Recycle Bin when
/// [recycle]; its answer is the shell's code, 0 for done.
typedef ShellDelete = Future<int> Function(List<String> paths, {required bool recycle});

/// Sends absolute paths to the trash. Processes, the platform and the Windows
/// shell come in through [ProcessRunner], [Env] and [ShellDelete], so every
/// command is a plain unit test.
class Trash {
  Trash({this.runner = const SystemProcessRunner(), Env? env, ShellDelete? shell})
      : env = env ?? Env.system(),
        _shell = shell ?? shellDelete;

  final ProcessRunner runner;
  final Env env;
  final ShellDelete _shell;

  /// Move [paths] (files or folders) away; with [permanent] they are removed
  /// for good instead. Throws [TrashException].
  ///
  /// The candidates of [commands] are tried in order, and the next one is tried
  /// only when a program is not installed. One that ran and failed is the
  /// answer: falling through to `rm` after a refused trash would delete for good
  /// what the user asked to keep.
  Future<void> send(List<String> paths, {bool permanent = false}) async {
    if (paths.isEmpty) return;
    if (env.isWindows) return _windows(paths, recycle: !permanent);
    ProcessException? missing;
    for (final (exe, args) in commands(paths, permanent: permanent)) {
      try {
        final result = await runner.run(exe, args);
        if (result.ok) return;
        final said = (result.stderr.trim().isEmpty ? result.stdout : result.stderr).trim();
        throw TrashException(said.isEmpty ? '$exe exited with ${result.exitCode}' : said);
      } on ProcessException catch (error) {
        missing = error;
      }
    }
    throw TrashException('Could not start ${missing?.executable}: ${missing?.message}');
  }

  /// Windows: the shell's own delete, with backslash paths, called in-process.
  Future<void> _windows(List<String> paths, {required bool recycle}) async {
    final code = await _shell([for (final path in paths) path.replaceAll('/', r'\')], recycle: recycle);
    if (code != 0) throw TrashException(shellDeleteMessage(code));
  }

  /// The programs to try on macOS and Linux, best first.
  List<(String, List<String>)> commands(List<String> paths, {bool permanent = false}) {
    if (env.isMacOS && !permanent) return [('osascript', ['-e', _finderScript(paths)])];
    return [
      // The FreeDesktop trash (`~/.local/share/Trash`): GNOME's `gio`, which KDE
      // and the rest read too, then trash-cli. Neither is installed everywhere,
      // and `rm` is the last resort: it removes for good.
      if (!env.isMacOS && !permanent) ...[
        ('gio', ['trash', '--', ...paths]),
        ('trash-put', ['--', ...paths]),
      ],
      ('rm', ['-r', '--', ...paths]),
    ];
  }

  /// macOS: Finder's own delete puts the items in the Trash.
  static String _finderScript(List<String> paths) {
    final items = paths.map((path) => 'POSIX file "${path.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"').join(', ');
    return 'tell application "Finder" to delete {$items}';
  }
}
