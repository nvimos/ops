import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/local/jobs.dart';
import 'package:nvimos_poc/local/system.dart';

import 'support/fake_system.dart';

void main() {
  group('LocalJobs', () {
    test('stdin is written to the process', () async {
      final process = _FakeProcess();
      final jobs = LocalJobs('C:/repo', start: (exe, args, {cwd}) async => process);
      await jobs.start('claude', const [], stdin: 'a prompt');
      expect(process.stdin, 'a prompt');
      await process.finish(0);
    });

    test('start emits a running job and finish a stopped one', () async {
      final process = _FakeProcess();
      final events = <Job>[];
      final stopped = Completer<Job>();
      final jobs = LocalJobs(
        'C:/repo',
        start: (exe, args, {cwd}) async => process,
        onEvent: (job) {
          events.add(job);
          if (!job.running && !stopped.isCompleted) stopped.complete(job);
        },
      );

      final id = await jobs.start('openspec', ['validate'], label: 'validate');

      expect(id, 1);
      expect(events.single.running, isTrue);
      expect(events.single.label, 'validate');
      expect(jobs.get(id)!.running, isTrue);
      expect(jobs.list().single.id, id);

      process.addStdout('working\n');
      process.addStderr('a note\n');
      await process.finish(0);

      final done = await stopped.future.timeout(const Duration(seconds: 2));
      expect(events, hasLength(2));
      expect(done.running, isFalse);
      expect(done.code, 0);
      expect(done.stdout, 'working\n');
      expect(done.stderr, 'a note\n');
      expect(jobs.get(id)!.running, isFalse);
    });

    test('ids increase, and the cwd defaults to the repo root', () async {
      final calls = <({String exe, List<String> args, String? cwd})>[];
      final started = <_FakeProcess>[];
      final allDone = Completer<void>();
      var finished = 0;
      final jobs = LocalJobs(
        'C:/repo',
        start: (exe, args, {cwd}) async {
          calls.add((exe: exe, args: args, cwd: cwd));
          final process = _FakeProcess();
          started.add(process);
          return process;
        },
        onEvent: (job) {
          if (!job.running && ++finished == 2 && !allDone.isCompleted) allDone.complete();
        },
      );

      final one = await jobs.start('claude', ['-p', 'hello']);
      final two = await jobs.start('openspec', ['list'], cwd: 'C:/repo/sub', label: 'os');

      expect([one, two], [1, 2]);
      expect(calls.first.cwd, 'C:/repo');
      expect(calls.first.exe, 'claude');
      expect(calls.first.args, ['-p', 'hello']);
      expect(calls.last.cwd, 'C:/repo/sub');
      expect(jobs.get(two)!.label, 'os');
      expect(jobs.list().map((job) => job.id), [one, two]);

      await started.first.finish(0);
      await started.last.finish(0);
      await allDone.future.timeout(const Duration(seconds: 2));
      expect(jobs.list().every((job) => !job.running), isTrue);
    });

    test('output is kept as a bounded tail', () async {
      final process = _FakeProcess();
      final stopped = Completer<Job>();
      final jobs = LocalJobs(
        'C:/repo',
        start: (exe, args, {cwd}) async => process,
        onEvent: (job) {
          if (!job.running && !stopped.isCompleted) stopped.complete(job);
        },
      );
      await jobs.start('claude', []);

      process.addStdout('o' * 9000);
      process.addStderr('e' * 5000);
      await process.finish(0);

      final done = await stopped.future.timeout(const Duration(seconds: 2));
      expect(done.stdout, hasLength(8000));
      expect(done.stdout, 'o' * 8000);
      expect(done.stderr, hasLength(4000));
      expect(done.stderr, 'e' * 4000);
    });

    test('cancel terminates the process and finishes the job', () async {
      final process = _FakeProcess();
      final stopped = Completer<Job>();
      final jobs = LocalJobs(
        'C:/repo',
        start: (exe, args, {cwd}) async => process,
        onEvent: (job) {
          if (!job.running && !stopped.isCompleted) stopped.complete(job);
        },
      );
      final id = await jobs.start('claude', []);

      expect(jobs.cancel(id), isTrue);
      final done = await stopped.future.timeout(const Duration(seconds: 2));

      expect(process.killed, isTrue);
      expect(done.running, isFalse);
      expect(done.code, -1);
      expect(jobs.get(id)!.running, isFalse);
      expect(jobs.cancel(id), isFalse);
    });

    test('a command outside the allow list is refused and leaves no job', () async {
      final jobs = LocalJobs(
        'C:/repo',
        start: (exe, args, {cwd}) async => _FakeProcess(),
      );

      await expectLater(jobs.start('rm', ['-rf', 'x']), throwsArgumentError);
      await expectLater(jobs.start('git', ['status']), throwsArgumentError);
      expect(jobs.list(), isEmpty);
    });
  });

  group('LocalJobs.cli', () {
    test('a missing executable answers code -1 with a message', () async {
      final runner = FakeRunner((call) => null);
      final jobs = LocalJobs('C:/repo', runner: runner);

      final result = await jobs.cli('openspec', ['list']);

      expect(result.code, -1);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('not installed'));
      expect(runner.calls.single.exe, 'openspec');
      expect(runner.calls.single.cwd, 'C:/repo');
    });

    test('a CLI result carries the code and both streams', () async {
      final runner = FakeRunner(
        (call) => const ProcessOutput(0, stdout: 'changes\n', stderr: ''),
      );
      final jobs = LocalJobs('C:/repo', runner: runner);

      final result = await jobs.cli('backlog', ['list', '--plain']);

      expect(result.code, 0);
      expect(result.stdout, 'changes\n');
      expect(result.stderr, isEmpty);
      expect(runner.calls.single.line, 'backlog list --plain');
    });

    test('only openspec and backlog may run', () async {
      final jobs = LocalJobs('C:/repo', runner: FakeRunner());

      await expectLater(jobs.cli('claude', ['-p']), throwsArgumentError);
      expect(jobs.list(), isEmpty);
    });
  });
}

/// A process whose output and exit a test drives by hand.
class _FakeProcess implements LocalProcess {
  final _out = StreamController<String>();
  final _err = StreamController<String>();
  final _exit = Completer<int>();
  bool killed = false;
  bool _closed = false;
  String? stdin;

  void addStdout(String text) => _out.add(text);

  void addStderr(String text) => _err.add(text);

  Future<void> finish(int code) async {
    if (_closed) return;
    _closed = true;
    await _out.close();
    await _err.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<String> get stdout => _out.stream;

  @override
  Stream<String> get stderr => _err.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    killed = true;
    unawaited(finish(-1));
  }

  @override
  void writeStdin(String text) => stdin = text;
}
