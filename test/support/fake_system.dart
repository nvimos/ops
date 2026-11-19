import 'dart:convert';
import 'dart:io';

import 'package:nvimos_poc/local/system.dart';

/// One call a [FakeRunner] saw.
class RunCall {
  const RunCall(this.exe, this.args, {this.cwd, this.stdin, this.detached = false});

  final String exe;
  final List<String> args;
  final String? cwd;
  final String? stdin;
  final bool detached;

  /// `exe arg arg`, for assertions.
  String get line => [exe, ...args].join(' ');

  @override
  String toString() => line;
}

/// Answers every process from [answer]; records each call in [calls]. An
/// answer of null means "cannot be started" (a [ProcessException]).
class FakeRunner implements ProcessRunner {
  FakeRunner([ProcessOutput? Function(RunCall call)? answer])
      : answer = answer ?? ((_) => const ProcessOutput(0));

  ProcessOutput? Function(RunCall call) answer;
  final List<RunCall> calls = [];

  @override
  Future<ProcessOutput> run(
    String exe,
    List<String> args, {
    String? cwd,
    String? stdin,
    Encoding encoding = systemEncoding,
  }) async {
    final call = RunCall(exe, args, cwd: cwd, stdin: stdin);
    calls.add(call);
    final out = answer(call);
    if (out == null) throw ProcessException(exe, args, 'not found', 2);
    return out;
  }

  @override
  Future<void> startDetached(String exe, List<String> args, {String? cwd}) async {
    final call = RunCall(exe, args, cwd: cwd, detached: true);
    calls.add(call);
    if (answer(call) == null) throw ProcessException(exe, args, 'not found', 2);
  }
}

/// A file system made of [dirs] (path to children) and [existing] paths.
/// Paths use forward slashes; a listing of an unknown directory throws, as an
/// unreadable one would.
class FakeLister implements DirectoryLister {
  FakeLister({Map<String, List<DirEntry>>? dirs, Set<String>? existing})
      : dirs = dirs ?? {},
        existing = existing ?? {};

  final Map<String, List<DirEntry>> dirs;
  final Set<String> existing;
  final List<String> listed = [];

  static String _clean(String path) => path.replaceAll(r'\', '/');

  @override
  Future<List<DirEntry>> list(String path) async {
    final clean = _clean(path);
    listed.add(clean);
    final found = dirs[clean];
    if (found == null) throw FileSystemException('cannot list', path);
    return found;
  }

  @override
  Future<bool> exists(String path) async {
    final clean = _clean(path);
    return existing.contains(clean) || dirs.containsKey(clean);
  }
}

/// The Windows shell's delete, recorded instead of done. [code] is what it
/// answers: 0 is done.
class FakeShell {
  FakeShell([this.code = 0]);

  int code;
  final List<({List<String> paths, bool recycle})> calls = [];

  Future<int> call(List<String> paths, {required bool recycle}) async {
    calls.add((paths: paths, recycle: recycle));
    return code;
  }
}
