import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'nvim.dart';
import 'temp_dirs.dart';

/// The snappy UI checks' fixture (`test/fixtures/tasks_snappy.json`, refreshed by
/// `make snapshot from=<planning repo>`): a real project's planning files (each as its lines) and
/// branches, without `backlog/docs/` and `legacy/`.
class SnappyFixture {
  SnappyFixture._(this.source, this.defaultBranch, this.files, this.branches);

  final String source, defaultBranch;
  final List<({String path, String text, int mtime})> files;
  final List<({String name, int ahead, int date})> branches;

  static SnappyFixture load([String path = 'test/fixtures/tasks_snappy.json']) {
    final j = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    return SnappyFixture._(
      j['source'] as String,
      j['default'] as String,
      [
        for (final f in (j['files'] as List).cast<Map<String, Object?>>())
          (path: f['path'] as String, text: (f['lines'] as List).cast<String>().join('\n'), mtime: f['mtime'] as int),
      ],
      [
        for (final b in (j['branches'] as List).cast<Map<String, Object?>>())
          (name: b['name'] as String, ahead: b['ahead'] as int, date: b['date'] as int),
      ],
    );
  }

  /// A temp git repo with the files on disk (their mtimes kept), one commit on the default branch,
  /// and each other branch [ahead] empty commits past it, dated as in the project. Made with one
  /// `git fast-import`, so it takes a second, not one process per commit. Deleted when the test
  /// file is done.
  Future<Directory> unpack() async {
    final d = keepForCleanup(await Directory.systemTemp.createTemp('nvimos_snappy_'));
    await git(d, ['init', '-q', '-b', defaultBranch]);
    for (final kv in {'core.autocrlf': 'false', 'core.fsmonitor': 'false'}.entries) {
      await git(d, ['config', kv.key, kv.value]);
    }
    for (final f in files) {
      final file = File('${d.path}/${f.path}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(f.text);
      file.setLastModifiedSync(DateTime.fromMillisecondsSinceEpoch(f.mtime));
    }

    final out = BytesBuilder();
    void line(String s) => out.add(utf8.encode('$s\n'));
    void data(String s) {
      final b = utf8.encode(s);
      line('data ${b.length}');
      out.add(b);
      line('');
    }

    for (var i = 0; i < files.length; i++) {
      line('blob');
      line('mark :${i + 1}');
      data(files[i].text);
    }
    final main = branches.where((b) => b.name == defaultBranch).firstOrNull;
    final base = files.length + 1;
    line('commit refs/heads/$defaultBranch');
    line('mark :$base');
    line('committer Testies Cohones <testies@example.com> ${main?.date ?? 0} +0000');
    data('plan');
    for (var i = 0; i < files.length; i++) {
      line('M 100644 :${i + 1} ${files[i].path}');
    }
    for (final b in branches.where((b) => b.name != defaultBranch)) {
      if (b.ahead == 0) {
        line('reset refs/heads/${b.name}');
        line('from :$base');
        continue;
      }
      for (var n = 0; n < b.ahead; n++) {
        line('commit refs/heads/${b.name}');
        line('committer Testies Cohones <testies@example.com> ${b.date} +0000');
        data('${b.name} ${n + 1}');
        if (n == 0) line('from :$base');
      }
    }
    final p = await Process.start('git', ['-c', 'core.fsmonitor=false', 'fast-import', '--quiet'], workingDirectory: d.path);
    p.stdin.add(out.takeBytes());
    await p.stdin.close();
    final err = p.stderr.transform(utf8.decoder).join();
    await p.stdout.drain<void>();
    if (await p.exitCode != 0) throw Exception('git fast-import: ${await err}');
    await git(d, ['reset', '-q']); // the index to the new commit; the files on disk already match
    return d;
  }
}
