import 'markdown.dart';

/// A status the app set by itself after a checkbox was ticked; [from] is what Undo puts back.
class AutoStatus {
  const AutoStatus(this.taskId, this.from, this.to);

  final String taskId, from, to;
}

/// The status a task should move to after a box was ticked, or null to leave it:
/// - every build step and every hand check ticked: Done
/// - every build step ticked, hand checks still open: Needs Test
/// Only from To Do, In Progress or Needs Test (never out of Done or Dropped, never backwards), and
/// only to a status the workspace has.
String? autoStatusAfterTick({
  required String status,
  required List<Check> build,
  required List<Check> verify,
  required List<String> statuses,
}) {
  const movable = ['To Do', 'In Progress', 'Needs Test'];
  if (!movable.contains(status) || (build.isEmpty && verify.isEmpty)) return null;
  if (build.any((c) => !c.done)) return null;
  final next = verify.every((c) => c.done) ? 'Done' : 'Needs Test';
  if (next == status || !statuses.contains(next)) return null;
  return next;
}
