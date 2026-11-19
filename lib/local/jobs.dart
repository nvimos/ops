/// Long-running commands for the app, and the two small CLIs.
///
/// The same rules the relay's `jobs.lua` and `files.lua` keep: only the
/// commands in [LocalJobs.allowed] may be started, only the tools in
/// [LocalJobs.clis] may run as a CLI, output is kept as a bounded tail, and a
/// missing executable is an answer rather than an exception for a CLI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../backend/models.dart';
import 'system.dart';

/// One started process, as the jobs watch it: decoded output and an exit code.
/// [kill] terminates it; its exit code then completes as usual.
abstract interface class LocalProcess {
  Stream<String> get stdout;
  Stream<String> get stderr;
  Future<int> get exitCode;

  /// Terminate the process. A process that already finished ignores this.
  void kill();
}

/// Starts a process for [LocalJobs]. The seam that keeps tests off the real
/// machine: a fake returns a [LocalProcess] driven by stream controllers.
typedef ProcessStarter = Future<LocalProcess> Function(
  String exe,
  List<String> args, {
  String? cwd,
});

/// A command started with [LocalJobs.start].
class _RunningJob {
  _RunningJob(this.id, this.label);

  final int id;
  final String label;
  bool running = true;
  int? code;
  String out = '';
  String err = '';

  void appendOut(String text) => out = _tail(out + text, 8000);
  void appendErr(String text) => err = _tail(err + text, 4000);

  Job public() => Job({
    'id': id,
    'label': label,
    'running': running,
    'code': code,
    'stdout': out,
    'stderr': err,
  });
}

/// The last [max] characters of [text].
String _tail(String text, int max) =>
    text.length <= max ? text : text.substring(text.length - max);

/// Starts, tracks and cancels the allowed long-running commands, and runs the
/// openspec/backlog CLI for the local backend.
///
/// Each job keeps a bounded tail of its output (8000 stdout, 4000 stderr) and
/// an increasing id. [onEvent] sees a running [Job] when the process starts and
/// a stopped one when it exits, which is what a session's jobs list needs.
class LocalJobs {
  LocalJobs(
    this.repoRoot, {
    ProcessStarter? start,
    this._runner = const SystemProcessRunner(),
    this.onEvent,
  }) : _start = start ?? _startSystem;

  /// The folder jobs and the CLI run in unless [LocalJobs.start] says otherwise.
  final String repoRoot;

  /// Commands a client may start.
  static const Set<String> allowed = {'claude', 'openspec', 'backlog'};

  /// Commands [cli] may run.
  static const Set<String> clis = {'openspec', 'backlog'};

  /// How long [cli] waits for its process.
  static const Duration cliTimeout = Duration(seconds: 30);

  /// Called with the running job when it starts and the stopped one when it
  /// exits; [Job.running] tells the two apart.
  final void Function(Job job)? onEvent;

  final ProcessStarter _start;
  final ProcessRunner _runner;

  final Map<int, _RunningJob> _jobs = {};
  final Map<int, LocalProcess> _processes = {};
  int _nextId = 0;

  /// Start [cmd] with [args] in [cwd] (the repo root by default). Returns the
  /// new job's id; throws [ArgumentError] for a command that is not allowed.
  Future<int> start(
    String cmd,
    List<String> args, {
    String? cwd,
    String? label,
  }) async {
    if (!allowed.contains(cmd)) {
      throw ArgumentError('nvimos: $cmd is not allowed as a job');
    }
    final id = ++_nextId;
    final job = _RunningJob(id, label ?? cmd);
    _jobs[id] = job;

    final LocalProcess process;
    try {
      process = await _start(cmd, args, cwd: cwd ?? repoRoot);
    } on ProcessException {
      _jobs.remove(id);
      throw StateError('nvimos: $cmd is not installed');
    } on Object {
      _jobs.remove(id);
      rethrow;
    }

    _processes[id] = process;
    onEvent?.call(job.public());
    unawaited(_watch(job, process));
    return id;
  }

  /// Every started job, oldest first.
  List<Job> list() {
    final ids = _jobs.keys.toList()..sort();
    return [for (final id in ids) _jobs[id]!.public()];
  }

  /// The job with [id], or null when no such job was started.
  Job? get(int id) => _jobs[id]?.public();

  /// Terminate the process of job [id]. True when it was still running.
  bool cancel(int id) {
    final process = _processes.remove(id);
    if (process == null) return false;
    process.kill();
    return true;
  }

  /// Run openspec or backlog with [args] in the repo root. A missing
  /// executable (or one that cannot start) answers `code: -1` with a message,
  /// as the relay does; a timeout does the same.
  Future<CliResult> cli(String cmd, List<String> args) async {
    if (!clis.contains(cmd)) {
      throw ArgumentError('nvimos: only openspec, backlog can run');
    }
    try {
      final result = await _runner
          .run(cmd, args, cwd: repoRoot, encoding: utf8)
          .timeout(cliTimeout);
      return CliResult({
        'code': result.exitCode,
        'stdout': result.stdout,
        'stderr': result.stderr,
      });
    } on ProcessException {
      return CliResult({'code': -1, 'stdout': '', 'stderr': '$cmd is not installed'});
    } on TimeoutException {
      return CliResult({
        'code': -1,
        'stdout': '',
        'stderr': '$cmd did not answer within ${cliTimeout.inSeconds}s',
      });
    } on Object catch (error) {
      return CliResult({'code': -1, 'stdout': '', 'stderr': '$error'});
    }
  }

  Future<void> _watch(_RunningJob job, LocalProcess process) async {
    final outDone = Completer<void>();
    final errDone = Completer<void>();
    final out = process.stdout.listen(
      job.appendOut,
      onError: (Object _) {
        if (!outDone.isCompleted) outDone.complete();
      },
      onDone: () {
        if (!outDone.isCompleted) outDone.complete();
      },
      cancelOnError: true,
    );
    final err = process.stderr.listen(
      job.appendErr,
      onError: (Object _) {
        if (!errDone.isCompleted) errDone.complete();
      },
      onDone: () {
        if (!errDone.isCompleted) errDone.complete();
      },
      cancelOnError: true,
    );

    final code = await process.exitCode;
    await Future.wait([outDone.future, errDone.future]);
    await out.cancel();
    await err.cancel();

    job
      ..running = false
      ..code = code;
    _processes.remove(job.id);
    onEvent?.call(job.public());
  }
}

/// The real process start, decoded as UTF-8 with malformed bytes replaced so a
/// batch file's code page cannot take the job down.
Future<LocalProcess> _startSystem(
  String exe,
  List<String> args, {
  String? cwd,
}) async {
  final process = await Process.start(exe, args, workingDirectory: cwd, runInShell: false);
  return _SystemLocalProcess(process);
}

class _SystemLocalProcess implements LocalProcess {
  _SystemLocalProcess(this._process);

  final Process _process;

  static const _decoder = Utf8Decoder(allowMalformed: true);

  @override
  Stream<String> get stdout => _process.stdout.transform(_decoder);

  @override
  Stream<String> get stderr => _process.stderr.transform(_decoder);

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() => _process.kill();
}
