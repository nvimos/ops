/// Writing a file that Windows keeps Hidden or System.
library;

import 'dart:io';

import 'git_repo.dart';
import 'system.dart';

/// Write a text file, getting past the Windows Hidden attribute.
///
/// Windows refuses `CreateFileW(..., CREATE_ALWAYS)` with ERROR_ACCESS_DENIED
/// when the existing file carries Hidden (or System), which is why overwriting
/// a dot file kept in the hidden style fails with `errno 5`. The fast path is a
/// plain write; only a refusal costs the `attrib` round trip. A cleared
/// attribute is always put back, including when the second write fails. This
/// is the same repair `~/AppData/Local/nvim/plugin/hidden-write.lua` does.
class HiddenWrite {
  const HiddenWrite({
    this.runner = const SystemProcessRunner(),
    this.isWindows = true,
  });

  final ProcessRunner runner;

  /// Off Windows a refusal is just a refusal: there is no `attrib`.
  final bool isWindows;

  Future<void> write(File file, String text) async {
    try {
      await file.writeAsString(text);
      return;
    } on FileSystemException catch (error) {
      if (!isWindows || error.osError?.errorCode != 5) rethrow;
      final restore = await clearHiddenAndSystem(file.path);
      try {
        await file.writeAsString(text);
      } finally {
        await restore();
      }
    }
  }

  /// Clear Hidden and System on [path]; returns the call that sets them again.
  ///
  /// Throws [GitException] with the manual command when they cannot be cleared:
  /// a write that would silently lose the attribute is not worth having.
  Future<Future<void> Function()> clearHiddenAndSystem(String path) async {
    final flags = await attributes(path);
    final toRestore = [
      if (flags.contains('H')) 'H',
      if (flags.contains('S')) 'S',
    ];
    if (toRestore.isEmpty) {
      throw GitException('cannot write $path: access denied, and the file is '
          'not Hidden or System (is it read-only, or open elsewhere?)');
    }
    final cleared = await _attrib(['-H', '-S', path]);
    if (!cleared) {
      throw GitException('$path is Hidden, so Windows refuses the write, and '
          '`attrib -H -S` failed. Run:  attrib -H -S "$path"');
    }
    final after = await attributes(path);
    if (after.contains('H') || after.contains('S')) {
      throw GitException('$path is still Hidden or System after `attrib -H -S`. '
          'Run:  attrib -H -S "$path"');
    }
    return () async {
      final ok = await _attrib([for (final flag in toRestore) '+$flag', path]);
      if (!ok) {
        throw GitException('could not set ${toRestore.join(' and ')} again on '
            '$path. Run:  attrib ${toRestore.map((flag) => '+$flag').join(' ')} "$path"');
      }
    };
  }

  /// The attribute letters `attrib` prints for [path], e.g. `A H`.
  ///
  /// The output is fixed-width flags followed by the path (`A    H        C:\…`),
  /// so the letters are read from the head of the line, up to the path itself.
  Future<Set<String>> attributes(String path) async {
    final result = await runner.run('attrib', [path]);
    if (!result.ok) return {};
    final text = result.stdout;
    final pathAt = text.toUpperCase().indexOf(path.toUpperCase());
    final head = pathAt > 0 ? text.substring(0, pathAt) : text;
    return {
      for (final rune in head.runes)
        if (String.fromCharCode(rune).toUpperCase() != String.fromCharCode(rune).toLowerCase())
          String.fromCharCode(rune),
    };
  }

  Future<bool> _attrib(List<String> args) async => (await runner.run('attrib', args)).ok;
}
