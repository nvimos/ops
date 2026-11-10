import '../backend/models.dart';
import 'model.dart';
import 'workspace.dart';

/// One reason something shows up in the inbox.
class InboxItem {
  InboxItem(this.section, this.why, {this.task, this.change, this.legacy, this.branch});
  final String section;
  final String why;
  final Task? task;
  final Change? change;
  final LegacyItem? legacy;
  final Branch? branch;
}

const sinceSection = 'Changed since you last looked';
const attentionSections = [
  'Waiting to be tried',
  'Branches with unreviewed commits',
  'In progress without a change',
  'Stale active changes',
  'Legacy notes marked untested',
];

/// The inbox: what changed since [lastSeen], then what needs attention.
List<InboxItem> inbox(Workspace ws, DateTime lastSeen, {DateTime? now}) {
  now ??= DateTime.now();
  final out = <InboxItem>[];
  bool open(Task t) => !t.archived && t.status != 'Done' && t.status != 'Dropped';

  for (final t in ws.tasks.where((t) => t.mtime.isAfter(lastSeen))) {
    out.add(InboxItem(sinceSection, 'task file changed', task: t));
  }
  for (final c in ws.changes.where((c) => c.mtime.isAfter(lastSeen) && ws.taskFor(c) == null)) {
    out.add(InboxItem(sinceSection, 'change files changed', change: c));
  }
  for (final b in ws.branches?.list ?? <Branch>[]) {
    if (b.name != ws.defaultBranch && b.date.isAfter(lastSeen)) {
      final t = ws.tasks.where((t) => ws.branchFor(t) == b.name).firstOrNull;
      out.add(InboxItem(sinceSection, 'new commits on ${b.name}', task: t, branch: b));
    }
  }

  for (final t in ws.tasks.where((t) => open(t) && t.status == 'Needs Test')) {
    final left = t.verify.where((c) => !c.done).length;
    out.add(InboxItem(attentionSections[0], left > 0 ? '$left verify steps left' : 'built, try it by hand', task: t));
  }
  for (final t in ws.tasks.where(open)) {
    final b = ws.branchFor(t);
    final n = b == null ? 0 : (ws.ahead[b] ?? 0);
    if (n > 0) out.add(InboxItem(attentionSections[1], '$n commits on $b', task: t));
  }
  for (final t in ws.tasks.where((t) => open(t) && t.status == 'In Progress' && ws.changeFor(t) == null)) {
    out.add(InboxItem(attentionSections[2], 'no OpenSpec change', task: t));
  }
  for (final c in ws.changes.where((c) => !c.archived && c.stage == 'Active')) {
    final days = now.difference(c.mtime).inDays;
    if (days >= 7) out.add(InboxItem(attentionSections[3], 'untouched for $days days', change: c));
  }
  for (final l in ws.legacy.where((l) => l.untested)) {
    out.add(InboxItem(attentionSections[4], '${l.file}, ${l.section}', legacy: l));
  }
  return out;
}
