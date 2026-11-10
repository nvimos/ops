import 'package:flutter/material.dart';

import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_parts.dart';
import 'icons.dart';
import 'rich.dart';

/// Identifies a milestone in the selection ('' = the open one).
class MilestoneKey {
  const MilestoneKey(this.name);
  final String name;
  @override
  bool operator ==(Object other) => other is MilestoneKey && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

const openMilestone = 'Next';

/// Changes of a milestone: archived ones between the previous milestone and this one, or for the
/// open milestone everything not archived yet.
List<Change> milestoneChanges(Workspace ws, String name) {
  if (name == openMilestone) return ws.changes.where((c) => !c.archived).toList();
  final m = ws.milestones.where((m) => m.name == name).firstOrNull;
  if (m == null) return [];
  return ws.changesIn(m)..sort((a, b) => b.archiveDate!.compareTo(a.archiveDate!));
}

String fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class MilestoneDetail extends StatelessWidget {
  const MilestoneDetail({
    super.key,
    required this.name,
    required this.ws,
    required this.onClose,
    required this.onChange,
  });

  final String name;
  final Workspace ws;
  final VoidCallback onClose;
  final void Function(Change c) onChange;

  @override
  Widget build(BuildContext context) {
    final m = ws.milestones.where((m) => m.name == name).firstOrNull;
    final list = milestoneChanges(ws, name);
    final done = list.where((c) => c.stage == 'Completed').length;
    final reqs = list.fold<int>(0, (n, c) => n + c.deltas.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(kicker: 'milestone', title: name, onClose: onClose),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            children: [
              if (m?.date != null) Prop('Closes', Text(fmtDate(m!.date!), style: T.body)),
              Prop('Changes', Text('${list.length}', style: T.body)),
              Prop('Progress', Progress(done, list.length, width: 140)),
              if (reqs > 0) Prop('Requirements', Text('$reqs changed', style: T.body)),
              Prop(
                'Source',
                Text(ws.milestonesFromFile ? 'milestones.md' : 'archive dates, one per month', style: T.small),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final c in list)
                HoverRow(
                  onTap: () => onChange(c),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                  child: Row(
                    children: [
                      StatusIcon(c.stage, size: 13),
                      const SizedBox(width: 10),
                      Expanded(child: RichLine(c.title, maxLines: 1)),
                      if (ws.taskFor(c) != null)
                        Text(
                          ws.taskFor(c)!.id,
                          style: const TextStyle(fontSize: 11, fontFamily: mono, color: C.faint),
                        ),
                      if (c.archiveDate != null) ...[
                        const SizedBox(width: 8),
                        Text(fmtDate(c.archiveDate!), style: T.tiny),
                      ],
                    ],
                  ),
                ),
              if (list.isEmpty) const Empty('No changes in this milestone.'),
            ],
          ),
        ),
      ],
    );
  }
}
