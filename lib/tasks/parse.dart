import 'markdown.dart';
import 'model.dart';

Task parseTask(String path, List<String> lines, {DateTime? mtime}) {
  final front = parseFrontMatter(lines);
  return Task(
    path: path,
    lines: lines,
    front: front,
    sections: parseSections(lines, from: front.end + 1),
    archived: path.contains('/archive/'),
    mtime: mtime ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// Requirements of a spec or delta file part: `### Requirement: Name` blocks with
/// `#### Scenario: Name` and their bullets, between [from] and [to].
List<(Requirement, List<String>)> parseRequirements(List<String> lines, int from, int to) {
  final out = <(Requirement, List<String>)>[];
  for (var i = from; i < to; i++) {
    final m = RegExp(r'^###\s+Requirement:\s*(.*)$').firstMatch(lines[i]);
    if (m == null) continue;
    var end = i + 1;
    while (end < to && !RegExp(r'^#{1,3}\s').hasMatch(lines[end])) {
      end++;
    }
    final text = <String>[];
    final scenarios = <Scenario>[];
    Scenario? cur;
    for (var j = i + 1; j < end; j++) {
      final l = lines[j];
      final sm = RegExp(r'^####\s+Scenario:\s*(.*)$').firstMatch(l);
      if (sm != null) {
        cur = Scenario(sm.group(1)!.trim(), []);
        scenarios.add(cur);
      } else if (cur != null) {
        if (l.trim().isNotEmpty) cur.steps.add(l.trim().replaceFirst(RegExp(r'^[-*]\s+'), ''));
      } else if (l.trim().isNotEmpty) {
        text.add(l.trim());
      }
    }
    out.add((Requirement(m.group(1)!.trim(), text.join(' '), scenarios, i, end), lines.sublist(i, end)));
  }
  return out;
}

/// Deltas of `specs/<capability>/spec.md` inside a change: `## ADDED|MODIFIED|REMOVED|RENAMED
/// Requirements` sections holding requirement blocks.
List<Delta> parseDeltas(String capability, List<String> lines) {
  final out = <Delta>[];
  final sections = parseSections(lines);
  for (final s in sections.where((s) => s.level == 2)) {
    final m = RegExp(r'^(ADDED|MODIFIED|REMOVED|RENAMED)\s+Requirements', caseSensitive: false).firstMatch(s.title);
    if (m == null) continue;
    final op = DeltaOp.values.byName(m.group(1)!.toLowerCase());
    for (final (r, raw) in parseRequirements(lines, s.start + 1, s.end)) {
      out.add(Delta(capability, op, r, raw));
    }
  }
  return out;
}

Spec parseSpec(String capability, Doc doc) {
  final purpose = findSection(doc.sections, (t) => t == 'purpose', level: 2);
  final reqs = findSection(doc.sections, (t) => t == 'requirements', level: 2);
  return Spec(
    capability,
    doc,
    purpose == null
        ? ''
        : doc.lines.sublist(purpose.start + 1, purpose.end).where((l) => l.trim().isNotEmpty).join(' '),
    reqs == null ? [] : parseRequirements(doc.lines, reqs.start + 1, reqs.end).map((e) => e.$1).toList(),
  );
}

/// Build changes from the files under `openspec/changes/` (path -> lines, path -> mtime).
List<Change> parseChanges(Map<String, List<String>> files, Map<String, DateTime> mtimes) {
  final byDir = <String, Map<String, List<String>>>{};
  final re = RegExp(r'^openspec/changes/((?:archive/)?[^/]+)/(.+)$');
  for (final e in files.entries) {
    final m = re.firstMatch(e.key);
    if (m == null || m.group(1) == 'archive') continue;
    byDir.putIfAbsent(m.group(1)!, () => {})[m.group(2)!] = e.value;
  }
  final out = <Change>[];
  for (final e in byDir.entries) {
    final archived = e.key.startsWith('archive/');
    final folder = archived ? e.key.substring(8) : e.key;
    final dm = RegExp(r'^(\d{4}-\d{2}-\d{2})-(.+)$').firstMatch(folder);
    final dir = 'openspec/changes/${e.key}';
    final deltas = <Delta>[];
    for (final f in e.value.entries) {
      final sm = RegExp(r'^specs/([^/]+)/spec\.md$').firstMatch(f.key);
      if (sm != null) deltas.addAll(parseDeltas(sm.group(1)!, f.value));
    }
    DateTime newest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final p in e.value.keys) {
      final t = mtimes['$dir/$p'];
      if (t != null && t.isAfter(newest)) newest = t;
    }
    Doc? doc(String name) => e.value[name] == null ? null : Doc('$dir/$name', e.value[name]!);
    out.add(
      Change(
        id: archived && dm != null ? dm.group(2)! : folder,
        dir: dir,
        archived: archived,
        archiveDate: archived && dm != null ? DateTime.tryParse(dm.group(1)!) : null,
        proposal: doc('proposal.md'),
        tasks: doc('tasks.md'),
        design: doc('design.md'),
        deltas: deltas,
        mtime: newest,
      ),
    );
  }
  return out;
}

/// Top-level checklist items of a legacy notes file, with their nested lines as notes.
List<LegacyItem> parseLegacy(String file, List<String> lines) {
  final out = <LegacyItem>[];
  var section = '';
  var fence = false;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.trimLeft().startsWith('```')) fence = !fence;
    if (fence) continue;
    final h = RegExp(r'^#{1,3}\s+(.*)$').firstMatch(l);
    if (h != null) {
      section = h.group(1)!.trim();
      continue;
    }
    final c = parseCheck(l, i);
    if (c == null || c.indent > 0) continue;
    final notes = <String>[];
    var j = i + 1;
    while (j < lines.length && (lines[j].startsWith(' ') || lines[j].startsWith('\t')) && lines[j].trim().isNotEmpty) {
      notes.add(lines[j].trimRight());
      j++;
    }
    out.add(LegacyItem(file: file, section: section, line: i, done: c.done, text: c.text, notes: notes));
  }
  return out;
}

/// `## Name (YYYY-MM-DD)` sections of milestones.md, oldest first, plus the open one.
List<Milestone> parseMilestones(List<String> lines) {
  final out = <Milestone>[];
  for (final l in lines) {
    final m = RegExp(r'^##\s+(.*?)\s*\((\d{4}-\d{2}-\d{2})\)\s*$').firstMatch(l);
    if (m != null) out.add(Milestone(m.group(1)!, DateTime.tryParse(m.group(2)!)));
  }
  out.sort((a, b) => a.date!.compareTo(b.date!));
  return out;
}

/// Milestones from archive dates when there is no milestones.md: one per month.
List<Milestone> monthlyMilestones(List<Change> changes) {
  final months = <String>{};
  for (final c in changes) {
    final d = c.archiveDate;
    if (d != null) months.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
  }
  final sorted = months.toList()..sort();
  return [
    for (final m in sorted) Milestone(m, DateTime(int.parse(m.substring(0, 4)), int.parse(m.substring(5)) + 1, 0)),
  ];
}

/// `statuses: [...]` and `project_name:` of backlog/config.yml.
/// `projects: [a, b]` in backlog/config.yml (not a Backlog.md key): the project labels of the repos
/// that share this planning folder, for the project filter.
List<String> parseBacklogProjects(List<String> lines) {
  for (final l in lines) {
    final m = RegExp(r'^projects:\s*\[(.*)\]').firstMatch(l);
    if (m != null) {
      return [
        for (final e in m.group(1)!.split(','))
          if (e.trim().isNotEmpty) e.trim().replaceAll(RegExp(r'''^["']|["']$'''), ''),
      ];
    }
  }
  return [];
}

(List<String>, String) parseBacklogConfig(List<String> lines) {
  var statuses = defaultStatuses;
  var name = '';
  for (final l in lines) {
    final s = RegExp(r'^statuses:\s*\[(.*)\]').firstMatch(l);
    if (s != null) {
      statuses = s.group(1)!.split(',').map((e) => e.trim().replaceAll(RegExp(r'''^["']|["']$'''), '')).toList();
    }
    final n = RegExp(r'''^project_name:\s*["']?(.*?)["']?\s*$''').firstMatch(l);
    if (n != null) name = n.group(1)!;
  }
  return (statuses, name);
}
