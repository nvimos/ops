// Which milestone each change belongs to: the one its task plans (`milestone:` in the task's front
// matter), else the dated milestone its archive date falls in, else the open one ("Next").

import 'model.dart';

/// The open milestone: changes not archived and not planned for a milestone.
const openMilestone = 'Next';

/// What [planMilestones] needs of a change.
typedef MilestoneInput = ({String key, bool archived, DateTime? archiveDate, String planned});

/// The closing date a milestone's name implies: `2027 Q1` / `2027-Q1` (the quarter's last day),
/// `2027-03` (the month's), `2027` (the year's); null for any other name.
DateTime? milestoneDate(String name) {
  final n = name.trim();
  final q = RegExp(r'^(\d{4})[ -]?Q([1-4])$', caseSensitive: false).firstMatch(n);
  if (q != null) return DateTime(int.parse(q.group(1)!), int.parse(q.group(2)!) * 3 + 1, 0);
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(n);
  if (m != null) return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!) + 1, 0);
  final y = RegExp(r'^(\d{4})$').firstMatch(n);
  if (y != null) return DateTime(int.parse(y.group(1)!), 12, 31);
  return null;
}

/// The milestones to show and each change's milestone name, by [MilestoneInput.key].
///
/// [dated] are the milestones from milestones.md or the archive months, oldest first.
/// - a planned change goes to its planned milestone, archived or not; a planned name that isn't
///   in [dated] becomes a milestone of its own, dated by [milestoneDate]
/// - an archived change goes to the first dated milestone that closes on or after its archive date
///   (none when it was archived after the last one)
/// - any other change goes to [openMilestone]
///
/// The result is sorted by date, undated planned milestones last by name.
({List<Milestone> milestones, Map<String, String> of}) planMilestones(
  List<Milestone> dated,
  Iterable<MilestoneInput> changes,
) {
  final names = {for (final m in dated) m.name};
  final planned = <String, Milestone>{};
  final of = <String, String>{};
  for (final c in changes) {
    final p = c.planned.trim();
    if (p.isNotEmpty) {
      of[c.key] = p;
      if (!names.contains(p)) planned[p] ??= Milestone(p, milestoneDate(p), planned: true);
    } else if (!c.archived) {
      of[c.key] = openMilestone;
    } else if (_window(dated, c.archiveDate) case final m?) {
      of[c.key] = m.name;
    }
  }
  final all = [...dated, ...planned.values]
    ..sort((a, b) {
      final x = a.date, y = b.date;
      if (x == null || y == null) return x != null ? -1 : (y != null ? 1 : a.name.compareTo(b.name));
      return x.compareTo(y);
    });
  return (milestones: all, of: of);
}

Milestone? _window(List<Milestone> dated, DateTime? archived) {
  if (archived == null) return null;
  for (final m in dated) {
    if (m.date != null && !archived.isAfter(m.date!)) return m;
  }
  return null;
}
