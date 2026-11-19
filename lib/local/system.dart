/// The three seams between the app and the machine: processes, the
/// environment, and directory listings.
///
/// Each has a real default and is small enough to fake in a test, so the
/// branches that need a machine in a particular state (a broken repository, a
/// file `attrib` cannot change, an unset `APPDATA`, a drive that is missing)
/// are plain unit tests. `GitDir.runCommand` stays the door for the rest of git.
library;

import 'dart:convert';
import 'dart:io';

/// What one finished process printed, already decoded.
class ProcessOutput {
  const ProcessOutput(this.exitCode, {this.stdout = '', this.stderr = ''});

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// Starts processes. The only place in `lib/` that calls `Process.run` or
/// `Process.start`.
abstract interface class ProcessRunner {
  /// Run [exe] with [args] to the end. [stdin], when given, is written and
  /// closed. Output is decoded with [encoding] (the system code page by
  /// default; git's `-z` output wants `utf8`). Throws [ProcessException] when
  /// [exe] cannot be started at all.
  Future<ProcessOutput> run(
    String exe,
    List<String> args, {
    String? cwd,
    String? stdin,
    Encoding encoding = systemEncoding,
  });

  /// Start [exe] detached from this app (an editor window), in [cwd] when
  /// given; returns at once.
  Future<void> startDetached(String exe, List<String> args, {String? cwd});
}

/// The real processes.
class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<ProcessOutput> run(
    String exe,
    List<String> args, {
    String? cwd,
    String? stdin,
    Encoding encoding = systemEncoding,
  }) async {
    if (stdin == null) {
      final result = await Process.run(
        exe,
        args,
        workingDirectory: cwd,
        runInShell: false,
        stdoutEncoding: encoding,
        stderrEncoding: encoding,
      );
      return ProcessOutput(
        result.exitCode,
        stdout: result.stdout as String,
        stderr: result.stderr as String,
      );
    }
    final process = await Process.start(exe, args, workingDirectory: cwd, runInShell: false);
    final out = process.stdout.transform(encoding.decoder).join();
    final err = process.stderr.transform(encoding.decoder).join();
    process.stdin.add(encoding.encode(stdin));
    await process.stdin.close();
    final code = await process.exitCode;
    return ProcessOutput(code, stdout: await out, stderr: await err);
  }

  @override
  Future<void> startDetached(String exe, List<String> args, {String? cwd}) async {
    await Process.start(exe, args, workingDirectory: cwd, mode: ProcessStartMode.detached);
  }
}

/// A read-only view of the environment, plus the platform question that goes
/// with it. The only place in `lib/` that reads `Platform.environment`.
class Env {
  const Env(this.values, {this.isWindows = true, this.isMacOS = false});

  /// The real environment of this process.
  factory Env.system() =>
      Env(Platform.environment, isWindows: Platform.isWindows, isMacOS: Platform.isMacOS);

  final Map<String, String> values;
  final bool isWindows;
  final bool isMacOS;

  /// The value of [name], or null when it is unset or blank. Windows names are
  /// case-insensitive, and `Platform.environment` already honours that; a fake
  /// map is matched exactly.
  String? operator [](String name) {
    final value = values[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// `USERPROFILE`, else `HOME`, else null.
  String? get home => this['USERPROFILE'] ?? this['HOME'];
}

/// One entry of a directory listing.
class DirEntry {
  const DirEntry(this.path, {required this.isDirectory, this.isLink = false});

  /// As the system printed it (backslashes on Windows).
  final String path;
  final bool isDirectory;
  final bool isLink;
}

/// Lists directories and asks whether a path exists. The browse walk, the
/// drive probe and the nvim-qt probe go through it.
abstract interface class DirectoryLister {
  /// The entries of [path], links not followed. Throws [FileSystemException]
  /// for a directory that cannot be read.
  Future<List<DirEntry>> list(String path);

  /// True when anything (file, folder, link) is at [path].
  Future<bool> exists(String path);
}

/// The real file system.
class SystemDirectoryLister implements DirectoryLister {
  const SystemDirectoryLister();

  @override
  Future<List<DirEntry>> list(String path) async {
    final entries = <DirEntry>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      entries.add(DirEntry(entity.path, isDirectory: entity is Directory, isLink: entity is Link));
    }
    return entries;
  }

  @override
  Future<bool> exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound;
}
