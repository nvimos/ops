import '../backend/models.dart';
import 'markdown.dart';
import 'model.dart';

/// Line-level edits of the planning files. Each carries `expect` (the line as the app read it), so
/// a file that changed meanwhile is refused instead of overwritten.

/// `status: X` in the task's front matter.
LineEdit taskStatusEdit(Task t, String status) {
  final i = t.statusLine;
  if (i < 0) throw StateError('${t.id} has no status line');
  return LineEdit(i, i + 1, ['status: ${yamlScalar(status)}'], expect: [t.lines[i]]);
}

/// `priority: X` in the front matter; added before the closing `---`, removed for ''.
LineEdit taskPriorityEdit(Task t, String priority) {
  final i = t.front.keyLines['priority'];
  final line = 'priority: $priority';
  if (i != null) {
    return LineEdit(i, i + 1, priority.isEmpty ? [] : [line], expect: [t.lines[i]]);
  }
  final end = t.front.end;
  if (end < 0) throw StateError('${t.id} has no front matter');
  return LineEdit(end, end, priority.isEmpty ? [] : [line], expect: []);
}

/// The two milestone lines of a file (the name, and the id of its milestone file next to it), at
/// [nameAt] / [idAt] (-1: missing): each replaced in place, a missing one added next to the other,
/// both added at [insertAt] when neither is there; an empty line takes its line out. The edits
/// never overlap, so they apply in any order.
List<LineEdit> _milestonePair(List<String> lines, int nameAt, int idAt, String nameLine, String idLine, int insertAt) {
  List<String> one(String l) => l.isEmpty ? [] : [l];
  if (nameAt >= 0 && idAt >= 0) {
    return [
      LineEdit(nameAt, nameAt + 1, one(nameLine), expect: [lines[nameAt]]),
      LineEdit(idAt, idAt + 1, one(idLine), expect: [lines[idAt]]),
    ];
  }
  final at = nameAt >= 0 ? nameAt : idAt;
  final both = [...one(nameLine), ...one(idLine)];
  if (at >= 0) return [LineEdit(at, at + 1, both, expect: [lines[at]])];
  return both.isEmpty ? [] : [LineEdit(insertAt, insertAt, both, expect: [])];
}

/// `milestone: <name>` (Backlog.md's key) and `milestone_id: m-<N>` (an Ops key, the milestone
/// file the name means; none for a name without a file) in the front matter; added before the
/// closing `---`, both removed for ''.
List<LineEdit> taskMilestoneEdits(Task t, String name, {String id = ''}) {
  final end = t.front.end;
  if (end < 0) throw StateError('${t.id} has no front matter');
  return _milestonePair(
    t.lines,
    t.front.keyLines['milestone'] ?? -1,
    t.front.keyLines['milestone_id'] ?? -1,
    name.isEmpty ? '' : 'milestone: ${yamlScalar(name)}',
    name.isEmpty || id.isEmpty ? '' : 'milestone_id: $id',
    end,
  );
}

/// The proposal's `Milestone: <name>` line and `Milestone-Id: m-<N>` right under it: replaced, else
/// added right under `Status:`, or without a Status line as a paragraph of their own under the
/// title (one blank line before and after, as the Status line sits); both removed for ''. Empty
/// without a proposal.
List<LineEdit> changeMilestoneEdits(Change c, String name, {String id = ''}) {
  final p = c.proposal;
  if (p == null) return [];
  final after = c.statusLine >= 0 ? c.statusLine : p.lines.indexWhere((l) => l.startsWith('# '));
  if (c.statusLine < 0 && c.milestoneLine < 0 && c.milestoneIdLine < 0 && name.isNotEmpty) {
    return [_paragraphUnder(p.lines, after, ['Milestone: $name', if (id.isNotEmpty) 'Milestone-Id: $id'])];
  }
  return _milestonePair(
    p.lines,
    c.milestoneLine,
    c.milestoneIdLine,
    name.isEmpty ? '' : 'Milestone: $name',
    name.isEmpty || id.isEmpty ? '' : 'Milestone-Id: $id',
    after + 1,
  );
}

/// [block] as a paragraph after line [at] (-1: at the top): one blank line before and one after,
/// reusing a blank line that is already there, so blank lines never double.
LineEdit _paragraphUnder(List<String> lines, int at, List<String> block) {
  bool blank(int i) => i >= 0 && i < lines.length && lines[i].trim().isEmpty;
  var i = at + 1;
  final before = at >= 0 && !blank(i);
  if (blank(i)) i++; // the blank line under the title stays the one before the block
  final after = i < lines.length && !blank(i);
  return LineEdit(i, i, [if (before) '', ...block, if (after) ''], expect: []);
}

/// The order of the Neovim tilde plugin (`genja/ext/tilde.lua`): open, done, in progress,
/// partly done, will not do, and round again.
const checkCycle = [' ', 'x', '.', '~', 'n'];

/// The mark after [mark]: a plain click ticks an open box and clears any other; [cycle] (Ctrl+click)
/// goes one step round [checkCycle].
String nextMark(String mark, {bool cycle = false}) {
  final m = mark == 'X' ? 'x' : mark;
  if (!cycle) return m == ' ' ? 'x' : ' ';
  final i = checkCycle.indexOf(m);
  return checkCycle[(i + 1) % checkCycle.length];
}

/// `- [ ]` -> `- [x]` and back on a checklist line; with [cycle], on to the next mark of [checkCycle].
LineEdit toggleCheckEdit(List<String> lines, Check c, {bool cycle = false}) {
  final old = lines[c.line];
  final m = RegExp(r'^(\s*[-*+] \[)([ xX.~n])(\].*)$').firstMatch(old);
  if (m == null) throw StateError('line ${c.line + 1} is not a checklist item');
  final now = '${m.group(1)}${nextMark(m.group(2)!, cycle: cycle)}${m.group(3)}';
  return LineEdit(c.line, c.line + 1, [now], expect: [old]);
}

/// The proposal's `Status: X (backlog TASK-n)` line, keeping what follows the status.
LineEdit? changeStatusEdit(Change c, String status) {
  final i = c.statusLine;
  if (i < 0 || c.proposal == null) return null;
  final old = c.proposal!.lines[i];
  final m = RegExp(r'^Status:\s*[^(]*?(\s*\(.*)?$').firstMatch(old);
  final tail = m?.group(1) ?? '';
  return LineEdit(i, i + 1, ['Status: $status$tail'], expect: [old]);
}

/// The status column of a task's row in index.tsv (task, status, change, title, file).
LineEdit? indexStatusEdit(List<String> index, String taskId, String status) {
  for (var i = 0; i < index.length; i++) {
    final cols = index[i].split('\t');
    if (cols.length > 1 && cols[0] == taskId) {
      cols[1] = status;
      return LineEdit(i, i + 1, [cols.join('\t')], expect: [index[i]]);
    }
  }
  return null;
}

/// Apply edits to lines in memory (the same way the backend does: bottom-up).
List<String> applyEdits(List<String> lines, List<LineEdit> edits) {
  final out = [...lines];
  final sorted = [...edits]..sort((a, b) => b.first.compareTo(a.first));
  for (final e in sorted) {
    out.replaceRange(e.first, e.last, e.lines);
  }
  return out;
}

String _slug(String title) {
  final s = title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(RegExp(r'\s+'), '-');
  return s.length > 60 ? s.substring(0, 60) : s;
}

String today() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A new Backlog.md task file, in the format the backlog CLI writes.
(String path, List<String> lines) newTaskFile({
  required int number,
  required String title,
  String status = 'To Do',
  List<String> labels = const [],
  List<String> description = const [],
  List<String> originalNotes = const [],
}) {
  final lines = <String>[
    '---',
    'id: TASK-$number',
    'title: ${yamlScalar(title)}',
    'status: ${yamlScalar(status)}',
    'assignee: []',
    "created_date: '${today()}'",
    if (labels.isEmpty) 'labels: []' else ...['labels:', for (final l in labels) '  - ${yamlScalar(l)}'],
    'dependencies: []',
    'ordinal: ${number * 1000}',
    '---',
    '',
    '## Description',
    '',
    if (description.isEmpty) title else ...description,
    if (originalNotes.isNotEmpty) ...['', '## Original notes', '', '```markdown', ...originalNotes, '```'],
  ];
  return ('backlog/tasks/task-$number - ${_slug(title)}.md', lines);
}
