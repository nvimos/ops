import 'markdown.dart';

/// Statuses of this workspace, in board order. Backlog.md's config may define its own.
const defaultStatuses = ['To Do', 'In Progress', 'Needs Test', 'Done', 'Dropped'];

/// A Backlog.md task file.
class Task {
  Task({
    required this.path,
    required this.lines,
    required this.front,
    required this.sections,
    required this.archived,
    required this.mtime,
  });

  final String path;
  final List<String> lines;
  final FrontMatter front;
  final List<Section> sections;
  final bool archived;
  final DateTime mtime;

  String get id => front.str('id');
  String get title => front.str('title');
  String get status => front.str('status');
  String get priority => front.str('priority');
  List<String> get labels => front.list('labels');
  List<String> get dependencies => front.list('dependencies');

  /// Backlog.md's `milestone:`, the milestone the task is planned for; empty when none.
  String get milestone => front.str('milestone').trim();
  String get created => front.str('created_date');
  /// A creation date recorded elsewhere in the task, for when `created_date` is no use: a label
  /// `created:2026-01-31` (or `created-2026-01-31`), else the front matter's `created_at` or
  /// `created`. Empty when there is none. How it is recorded is not settled yet.
  String get createdHint {
    for (final l in labels) {
      final m = _createdTag.firstMatch(l);
      if (m != null) return m.group(1)!;
    }
    final v = front.str('created_at').isNotEmpty ? front.str('created_at') : front.str('created');
    return v;
  }

  static final _createdTag = RegExp(r'^created[:=-](\d{4}-\d{2}-\d{2})');
  int get ordinal => int.tryParse(front.str('ordinal')) ?? 0;
  late final int number = int.tryParse(id.replaceAll(_nonDigit, '')) ?? 0;
  static final _nonDigit = RegExp(r'\D');

  Section? section(String name) => findSection(sections, (t) => t == name.toLowerCase(), level: 2);

  List<Block> get description {
    final s = section('Description');
    return s == null ? [] : blocksIn(lines, s.start + 1, s.end);
  }

  List<Check> get acceptance => checksIn(lines, section('Acceptance Criteria'));
  List<Check> get verify => checksIn(lines, section('Verify'));
  List<Check> get definitionOfDone => checksIn(lines, section('Definition of Done'));

  /// The fenced block under "Original notes", if any.
  List<String> get originalNotes {
    final s = section('Original notes');
    if (s == null) return [];
    for (final b in blocksIn(lines, s.start + 1, s.end)) {
      if (b is CodeBlock) return b.lines;
    }
    return [];
  }

  /// Sections other than the ones rendered on their own.
  List<Section> get otherSections => sections
      .where(
        (s) =>
            s.level == 2 &&
            !{
              'description',
              'acceptance criteria',
              'verify',
              'definition of done',
              'original notes',
            }.contains(s.title.toLowerCase()),
      )
      .toList();

  int get statusLine => front.keyLines['status'] ?? -1;
}

enum DeltaOp { added, modified, removed, renamed }

class Scenario {
  Scenario(this.name, this.steps);
  final String name;
  final List<String> steps;
}

/// A requirement, in a living spec or in a change's delta.
class Requirement {
  Requirement(this.name, this.text, this.scenarios, this.start, this.end);
  final String name;
  final String text;
  final List<Scenario> scenarios;

  /// Lines of the `### Requirement:` block in its file: [start, end).
  final int start, end;
}

class Delta {
  Delta(this.capability, this.op, this.requirement, this.lines);
  final String capability;
  final DeltaOp op;
  final Requirement requirement;

  /// The raw lines of the requirement block (for merging into the living spec).
  final List<String> lines;
}

/// An OpenSpec change folder.
class Change {
  Change({
    required this.id,
    required this.dir,
    required this.archived,
    required this.archiveDate,
    required this.proposal,
    required this.tasks,
    required this.design,
    required this.deltas,
    required this.mtime,
  });

  final String id;
  final String dir;
  final bool archived;
  final DateTime? archiveDate;
  final Doc? proposal, tasks, design;
  final List<Delta> deltas;
  final DateTime mtime;

  String get title {
    final h1 = proposal?.sections.where((s) => s.level == 1).firstOrNull;
    return h1?.title ?? id;
  }

  /// The proposal's `Status: X (backlog TASK-n)` line.
  int get statusLine => proposal?.lines.indexWhere((l) => l.startsWith('Status:')) ?? -1;

  String get status {
    final i = statusLine;
    if (i < 0) return archived ? 'Done' : 'To Do';
    final m = RegExp(r'^Status:\s*([^(]+?)\s*(\(|$)').firstMatch(proposal!.lines[i]);
    return m?.group(1) ?? '';
  }

  /// The linked Backlog.md task id, from the Status line.
  String? get taskId {
    final i = statusLine;
    if (i < 0) return null;
    return RegExp(r'TASK-\d+', caseSensitive: false).firstMatch(proposal!.lines[i])?.group(0)?.toUpperCase();
  }

  /// Draft / Active / Completed, as OpenSpec's view groups changes.
  String get stage {
    if (archived || status == 'Done') return 'Completed';
    if (allChecks.isEmpty || allChecks.every((c) => !c.done)) return 'Draft';
    return 'Active';
  }

  List<Check> get allChecks => tasks == null ? [] : checksIn(tasks!.lines, Section(0, '', -1, tasks!.lines.length));

  /// Build and Verify checklists of tasks.md (`## 1. Build`, `## 2. Verify`); other `##`
  /// sections come as their own groups.
  List<(String, List<Check>)> get checkGroups {
    final t = tasks;
    if (t == null) return [];
    return [
      for (final s in t.sections.where((s) => s.level == 2))
        (s.title.replaceFirst(RegExp(r'^\d+\.\s*'), ''), checksIn(t.lines, s)),
    ];
  }

  Section? proposalSection(String name) =>
      proposal == null ? null : findSection(proposal!.sections, (t) => t == name.toLowerCase(), level: 2);
}

/// A Markdown file read into lines and sections.
class Doc {
  Doc(this.path, this.lines) : sections = parseSections(lines);
  final String path;
  final List<String> lines;
  final List<Section> sections;

  List<Block> body(Section s) => blocksIn(lines, s.start + 1, s.end);
}

/// A capability of the living spec, `openspec/specs/<capability>/spec.md`.
class Spec {
  Spec(this.capability, this.doc, this.purpose, this.requirements);
  final String capability;
  final Doc doc;
  final String purpose;
  final List<Requirement> requirements;
}

/// One top-level checklist bullet of the old notes in `legacy/`.
class LegacyItem {
  LegacyItem({
    required this.file,
    required this.section,
    required this.line,
    required this.done,
    required this.text,
    required this.notes,
  });

  final String file;
  final String section;
  final int line;
  final bool done;
  final String text;
  final List<String> notes;

  bool get untested => '$text ${notes.join(' ')}'.toLowerCase().contains('untested');

  /// Short commit hashes mentioned in the item, e.g. `(b829ae5)`.
  List<String> get commits =>
      RegExp(r'\b[0-9a-f]{7,10}\b').allMatches('$text ${notes.join(' ')}').map((m) => m.group(0)!).toSet().toList();

  /// Group key: the year in the file name (todo-2027.md), else the file name.
  String get group {
    final m = RegExp(r'(20\d\d)').firstMatch(file);
    return m?.group(1) ?? file.replaceAll('.md', '');
  }
}

/// A milestone: a name and the date it closes. Changes planned for it (their task's `milestone:`)
/// belong to it, and so do unplanned changes archived on or before it (and after the previous one).
class Milestone {
  Milestone(this.name, this.date, {this.planned = false});
  final String name;
  final DateTime? date; // null: a planned name without a date in it
  /// Only named by a task's `milestone:`, not in milestones.md or an archive month.
  final bool planned;
}
