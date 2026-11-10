import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ws,
      builder: (context, _) {
        final t = ws.task(taskId);
        if (t == null) return const Empty('Task not found.');
        final verify = t.verify, ac = t.acceptance;
        Future<void> status(String s) async => onError?.call(await ws.setTaskStatus(t, s));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => onOpenTask?.call(t.id),
                    child: Text(
                      t.id,
                      style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.accent),
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichLine(t.title, style: T.title, maxLines: 3),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StatusIcon(t.status),
                      const SizedBox(width: 6),
                      Text(t.status, style: T.small),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                children: [
                  Row(
                    children: [
                      const Text('VERIFY', style: T.section),
                      const Spacer(),
                      Progress(verify.where((c) => c.done).length, verify.length),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (verify.isEmpty) const Text('No verify steps in this task.', style: T.small),
                  for (final c in verify)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: CheckRow(
                        c,
                        onTap: () async => onError?.call(await ws.toggleCheck(t.path, c)),
                        onTask: onOpenTask,
                      ),
                    ),
                  if (ac.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('ACCEPTANCE CRITERIA', style: T.section),
                    const SizedBox(height: 8),
                    for (final c in ac)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: CheckRow(
                          c,
                          onTap: () async => onError?.call(await ws.toggleCheck(t.path, c)),
                          onTask: onOpenTask,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: C.border)),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  SmallButton('In Progress', onPressed: t.status == 'In Progress' ? null : () => status('In Progress')),
                  SmallButton('Needs Test', onPressed: t.status == 'Needs Test' ? null : () => status('Needs Test')),
                  SmallButton('Done', primary: true, onPressed: t.status == 'Done' ? null : () => status('Done')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
