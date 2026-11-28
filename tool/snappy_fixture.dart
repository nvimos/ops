// Snapshots a project's planning files and branches into the snappy UI checks' fixture.
//
//   dart run tool/snappy_fixture.dart <planning repo> [out]
//
// Reads only: the files the Tasks mode parses (tracked and untracked, as on disk) with their mtimes,
// and every local branch with its commits ahead of the default branch and its last commit date:
// - backlog/config.yml, task files (backlog/tasks, backlog/archive/tasks), Backlog.md milestone files
//   (backlog/milestones, backlog/archive/milestones), milestones.md and index.tsv
// - openspec/specs/<capability>/spec.md, and of each change only proposal.md, tasks.md, design.md and
//   its spec deltas (specs/<capability>/spec.md); other notes in a change folder are not read
// Left out: backlog/docs/ (never read), legacy/ (out of the checks' scope, leaving the app).
//
// The checks measure structure: what is counted, listed, linked and how many widgets a detail panel
// builds follows the front matter, headings, checklists and the number of lines, not how long a
// prose line is. So every file keeps every line and its structure verbatim, and each prose line is
// cut to its first words (at most [_prose] characters, at a word boundary), keeping its indentation
// and list marker. The [_fullTasks] longest task files and [_fullProposals] longest proposals stay
// whole (`"full": true`): the worst-case detail panel. It also keeps the project's notes out of the
// fixture.
//
// Writes one plain JSON (default test/fixtures/tasks_snappy.json), indented by one space, each
// file's text as a list of lines (joined with '\n' it is the file), so a refreshed snapshot diffs
// line by line; test/support/snappy.dart unpacks it into a temp git repo.
import 'dart:convert';
import 'dart:io';

const _prose = 40, _fullTasks = 3, _fullProposals = 2;

final _taskFile = RegExp(r'^backlog/(archive/)?tasks/task-[^/]*\.md$');
final _proposal = RegExp(r'^openspec/changes/(archive/)?[^/]+/proposal\.md$');

/// The planning files the Tasks mode parses.
bool _read(String p) =>
    p == 'backlog/config.yml' ||
    p == 'milestones.md' ||
    p == 'index.tsv' ||
    _taskFile.hasMatch(p) ||
    RegExp(r'^backlog/(archive/)?milestones/[^/]+\.md$').hasMatch(p) ||
    RegExp(r'^openspec/specs/[^/]+/spec\.md$').hasMatch(p) ||
    RegExp(r'^openspec/changes/(archive/)?[^/]+/(proposal|tasks|design)\.md$').hasMatch(p) ||
    RegExp(r'^openspec/changes/(archive/)?[^/]+/specs/[^/]+/spec\.md$').hasMatch(p);

/// A line kept as it is: headings, checklist items, the change's Status / Milestone lines, fences,
/// table rows, blank lines (front matter is kept by [_shorten]).
final _structure = RegExp(r'^\s*(#|[-*+] \[.\] |```|\||(Status|Milestone|Milestone-Id):)|^\s*$');

/// The indentation and list or quote marker of a prose line, kept in front of its shortened text.
final _lead = RegExp(r'^(\s*(?:[-*+] |\d+[.)] |> )*)(.*)$');

String _cut(String text) {
  if (text.length <= _prose) return text;
  final space = text.lastIndexOf(' ', _prose);
  return (space > 0 ? text.substring(0, space) : text.substring(0, _prose)).trimRight();
}

/// [lines] with every prose line cut to its first words; front matter and structure stay verbatim.
List<String> _shorten(List<String> lines) {
  final out = <String>[];
  var front = lines.isNotEmpty && lines.first.trim() == '---';
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (front) {
      out.add(l);
      if (i > 0 && l.trim() == '---') front = false;
      continue;
    }
    if (_structure.hasMatch(l)) {
      out.add(l);
      continue;
    }
    final m = _lead.firstMatch(l)!;
    out.add('${m.group(1)}${_cut(m.group(2)!)}');
  }
  return out;
}

/// The [n] longest of [paths] matching [re], by size.
Set<String> _longest(Map<String, String> texts, RegExp re, int n) {
  final hits = texts.keys.where(re.hasMatch).toList()..sort((a, b) => texts[b]!.length.compareTo(texts[a]!.length));
  return hits.take(n).toSet();
}

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
      if (_read(p) && File('$repo/$p').existsSync()) p,
  ]..sort();
  final texts = {for (final p in paths) p: File('$repo/$p').readAsStringSync()};
  final full = {..._longest(texts, _taskFile, _fullTasks), ..._longest(texts, _proposal, _fullProposals)};
  final files = [
    for (final p in paths)
      {
        'path': p,
        'mtime': File('$repo/$p').lastModifiedSync().millisecondsSinceEpoch,
        if (full.contains(p)) 'full': true,
        'lines': full.contains(p) ? texts[p]!.split('\n') : _shorten(texts[p]!.split('\n')),
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
  await out.writeAsString('${const JsonEncoder.withIndent(' ').convert(blob)}\n');
  stdout.writeln('   wrote ${out.path}');
  stdout.writeln('   files ${files.length}');
  for (final p in full.toList()..sort()) {
    stdout.writeln('    full $p');
  }
  stdout.writeln('branches ${branches.length}');
}
