import 'package:material_ui/material_ui.dart';

import '../../tasks/browser.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'change_detail.dart';
import 'detail_parts.dart';

/// A milestone: its date, progress and requirement count, then its changes.
class MilestoneDetail extends StatelessWidget {
  const MilestoneDetail({
    super.key,
    required this.name,
    required this.ws,
    required this.onClose,
    this.widen,
    required this.onChange,
  });

  final String name;
  final Workspace ws;
  final VoidCallback onClose;
  final PanelWiden? widen;
  final void Function(Change c) onChange;

  @override
  Widget build(BuildContext context) {
    final list = milestoneChanges(ws, name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(kicker: 'milestone', title: name, onClose: onClose, widen: widen),
        _MilestoneProps(name: name, ws: ws, changes: list),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? const Empty('No changes in this milestone.')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) =>
                      ChangeLine(change: list[i], taskId: ws.taskFor(list[i])?.id, onTap: () => onChange(list[i])),
                ),
        ),
      ],
    );
  }
}

class _MilestoneProps extends StatelessWidget {
  const _MilestoneProps({required this.name, required this.ws, required this.changes});

  final String name;
  final Workspace ws;
  final List<Change> changes;

  @override
  Widget build(BuildContext context) {
    final m = ws.milestones.where((m) => m.name == name).firstOrNull;
    final date = m?.date;
    final done = changes.where((c) => c.stage == 'Completed').length;
    final reqs = changes.fold<int>(0, (n, c) => n + c.deltas.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: [
          if (date != null) Prop('Closes', Text(fmtDate(date), style: T.body)),
          Prop('Changes', Text('${changes.length}', style: T.body)),
          Prop('Progress', Progress(done, changes.length, width: 140)),
          if (reqs > 0) Prop('Requirements', Text('$reqs changed', style: T.body)),
          Prop('Source', Text(_source(m), style: T.small)),
        ],
      ),
    );
  }

  String _source(Milestone? m) {
    if (m == null) return 'changes not archived and not planned';
    if (m.planned) return "the tasks' milestone: field";
    return ws.milestonesFromFile ? 'milestones.md' : 'archive dates, one per month';
  }
}
