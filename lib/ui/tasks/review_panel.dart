import 'package:material_ui/material_ui.dart';

import '../../tasks/markdown.dart';
import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_parts.dart';
import 'icons.dart';
import 'rich.dart';

/// Beside the diff while reviewing a task's branch: its Verify list and status buttons, so trying
/// it by hand and ticking steps happen in one place.
class ReviewPanel extends StatelessWidget {
  const ReviewPanel({super.key, required this.ws, required this.taskId, this.onOpenTask, this.onError});

  final Workspace ws;
  final String taskId;
  final void Function(String id)? onOpenTask;
  final void Function(String? err)? onError;

  /// The statuses a review ends in, the last one primary.
  static const outcomes = ['In Progress', 'Needs Test', 'Done'];

  Future<void> _status(Task t, String s) async => onError?.call(await ws.setTaskStatus(t, s));

  Future<void> _check(Task t, Check c, bool cycle) async =>
      onError?.call(await ws.toggleCheck(t.path, c, cycle: cycle));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ws,
    builder: (context, _) {
      final t = ws.task(taskId);
      if (t == null) return const Empty('Task not found.');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewTitle(task: t, onOpenTask: onOpenTask),
          const Divider(height: 1),
          Expanded(child: _ReviewChecks(task: t, onCheck: (c, cycle) => _check(t, c, cycle), onTask: onOpenTask)),
          _Outcomes(current: t.status, onPick: (s) => _status(t, s)),
        ],
      );
    },
  );
}

class _ReviewTitle extends StatelessWidget {
  const _ReviewTitle({required this.task, required this.onOpenTask});

  final Task task;
  final void Function(String id)? onOpenTask;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onOpenTask == null ? null : () => onOpenTask!(task.id),
          child: Text(task.id, style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.accent)),
        ),
        const SizedBox(height: 4),
        RichLine(task.title, style: T.title, maxLines: 3),
        const SizedBox(height: 8),
        Row(children: [StatusIcon(task.status), const SizedBox(width: 6), Text(task.status, style: T.small)]),
      ],
    ),
  );
}

/// Verify first (that is what a review tries), then acceptance criteria.
class _ReviewChecks extends StatelessWidget {
  const _ReviewChecks({required this.task, required this.onCheck, required this.onTask});

  final Task task;
  final void Function(Check c, bool cycle) onCheck;
  final void Function(String id)? onTask;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 12),
    children: [
      ChecksSection(title: 'Verify', checks: task.verify, onCheck: onCheck, onTask: onTask),
      if (task.verify.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('No verify steps in this task.', style: T.small)),
      if (task.acceptance.isNotEmpty)
        ChecksSection(title: 'Acceptance criteria', checks: task.acceptance, onCheck: onCheck, onTask: onTask),
    ],
  );
}

class _Outcomes extends StatelessWidget {
  const _Outcomes({required this.current, required this.onPick});

  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border))),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in ReviewPanel.outcomes)
          SmallButton(s, primary: s == ReviewPanel.outcomes.last, onPressed: s == current ? null : () => onPick(s)),
      ],
    ),
  );
}
