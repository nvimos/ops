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

/// `- [ ]` <-> `- [x]` on a checklist line.
LineEdit toggleCheckEdit(List<String> lines, Check c) {
  final old = lines[c.line];
  final m = RegExp(r'^(\s*[-*+] \[)([ xX])(\].*)$').firstMatch(old);
  if (m == null) throw StateError('line ${c.line + 1} is not a checklist item');
  final now = '${m.group(1)}${m.group(2) == ' ' ? 'x' : ' '}${m.group(3)}';
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
