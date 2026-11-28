// Snapshots a project's planning files and branches into the snappy UI checks' fixture.
//
//   dart run tool/snappy_fixture.dart <planning repo> [out]
//
// Reads only: the files the Tasks mode loads (backlog/ and openspec/ as .md / .yml, plus
// milestones.md and index.tsv; tracked and untracked, as on disk) with their mtimes, and every
// local branch with its commits ahead of the default branch and its last commit date. Left out:
// backlog/docs/ (the Tasks mode never reads it) and legacy/ (Legacy notes are out of the checks'
// scope and leaving the app). Writes one plain, pretty-printed JSON (default
// test/fixtures/tasks_snappy.json), each file's text as a list of lines (`text.split('\n')`, so
// joining them gives the file back exactly), so a refreshed snapshot diffs line by line and git
// compresses and deltas it itself; test/support/snappy.dart unpacks it into a temp git repo.
import 'dart:convert';
import 'dart:io';

Future<String> _git(String repo, List<String> args) async {
  final r = await Process.run('git', ['-c', 'core.fsmonitor=false', ...args], workingDirectory: repo);
  if (r.exitCode != 0) throw Exception('git ${args.join(' ')}: ${r.stderr}');
  return r.stdout as String;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/snappy_fixture.dart <planning repo> [out]');
    exit(2);
  }
  final repo = args[0];
  final out = File(args.length > 1 ? args[1] : 'test/fixtures/tasks_snappy.json');
  final listed = await _git(repo, [
    'ls-files', '--cached', '--others', '--exclude-standard', '--', 'backlog', 'openspec', 'milestones.md', 'index.tsv',
  ]);
  final paths = [
    for (final p in const LineSplitter().convert(listed))
      if (!p.startsWith('backlog/docs/') && (p.endsWith('.md') || p.endsWith('.yml') || p == 'index.tsv')) p,
  ]..sort();
  final files = [
    for (final p in paths)
      if (File('$repo/$p').existsSync())
        {
          'path': p,
          'mtime': File('$repo/$p').lastModifiedSync().millisecondsSinceEpoch,
          'lines': File('$repo/$p').readAsStringSync().split('\n'),
        },
  ];
  final names = const LineSplitter().convert(await _git(repo, ['for-each-ref', '--format=%(refname:short)', 'refs/heads']));
  final main = names.contains('main') ? 'main' : (names.contains('master') ? 'master' : names.first);
  final branches = [
    for (final b in names)
      {
        'name': b,
        'ahead': b == main ? 0 : int.parse((await _git(repo, ['rev-list', '--count', '$main..$b'])).trim()),
        'date': int.parse((await _git(repo, ['log', '-1', '--format=%ct', b])).trim()),
      },
  ];
  final blob = {
    'source': repo.replaceAll('\\', '/').split('/').last,
    'captured': DateTime.now().toUtc().toIso8601String(),
    'default': main,
    'files': files,
    'branches': branches,
  };
  await out.parent.create(recursive: true);
  await out.writeAsString('${const JsonEncoder.withIndent('  ').convert(blob)}\n');
  stdout.writeln('   wrote ${out.path}');
  stdout.writeln('   files ${files.length}');
  stdout.writeln('branches ${branches.length}');
}
