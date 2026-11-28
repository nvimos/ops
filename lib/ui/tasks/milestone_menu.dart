import 'package:material_ui/material_ui.dart';

import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';

/// The milestones a task or a proposal can be planned for, by date ('Next' is not one: it is
/// where the unplanned open changes go).
List<String> milestoneChoices(Workspace ws) => [for (final m in ws.milestones) m.name];

/// The menu value that asks for a new milestone's name.
const _newMilestone = '\u0000new';

String milestoneLabel(String name) => name.isEmpty ? 'No milestone' : name;

List<PopupMenuEntry<String>> _entries(List<String> choices, String current, {String prefix = ''}) => [
  PopupMenuItem(value: '', height: 32, enabled: current.isNotEmpty, child: Text('${prefix}No milestone', style: T.body)),
  if (choices.isNotEmpty) const PopupMenuDivider(height: 8),
  for (final c in choices)
    PopupMenuItem(value: c, height: 32, enabled: c != current, child: Text('$prefix$c', style: T.body)),
  const PopupMenuDivider(height: 8),
  PopupMenuItem(value: _newMilestone, height: 32, child: Text('${prefix}New milestone…', style: T.body)),
];

/// What a pick means: a milestone name, '' for none, or null (cancelled, or the new name dialog
/// was closed).
Future<String?> _resolve(BuildContext context, String? picked) async {
  if (picked != _newMilestone) return picked;
  return showDialog<String>(context: context, builder: (_) => const MilestoneNameDialog());
}

/// The Milestone property of a task or a change: shows the planned milestone, a click picks
/// another one, none, or a new one.
class MilestoneMenu extends StatelessWidget {
  const MilestoneMenu({super.key, required this.value, required this.choices, required this.tip, required this.onPick});

  final String value;
  final List<String> choices;
  final String tip;
  final ValueChanged<String> onPick;

  Future<void> _picked(BuildContext context, String v) async {
    final name = await _resolve(context, v);
    if (name != null) onPick(name);
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tip,
    color: C.surface2,
    onSelected: (v) => _picked(context, v),
    itemBuilder: (_) => _entries(choices, value),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: SelectionContainer.disabled(child: _MilestoneValue(value)),
    ),
  );
}

class _MilestoneValue extends StatelessWidget {
  const _MilestoneValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.flag_outlined, size: 14, color: value.isEmpty ? C.faint : C.muted),
      const SizedBox(width: 8),
      Text(milestoneLabel(value), style: value.isEmpty ? T.small : T.body),
    ],
  );
}

/// The right-click menu of a change in the Milestones view: "Move to …" each milestone, none, or a
/// new one. Returns the name picked ('' for none), or null.
Future<String?> showMoveToMenu(BuildContext context, Offset at, {required List<String> choices, required String current}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final picked = await showMenu<String>(
    context: context,
    color: C.surface2,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: _entries(choices, current, prefix: 'Move to '),
  );
  if (picked == null || !context.mounted) return null;
  return _resolve(context, picked);
}

/// Asks for the name of a new milestone (`2027 Q1`, `2027-03`, `v1 launch`).
class MilestoneNameDialog extends StatefulWidget {
  const MilestoneNameDialog({super.key});

  @override
  State<MilestoneNameDialog> createState() => _MilestoneNameDialogState();
}

class _MilestoneNameDialogState extends State<MilestoneNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final n = _name.text.trim();
    if (n.isNotEmpty) Navigator.of(context).pop(n);
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: C.surface,
    title: Text('New milestone', style: T.title),
    content: SizedBox(
      width: 320,
      child: TextField(
        controller: _name,
        autofocus: true,
        style: T.body,
        decoration: const InputDecoration(hintText: '2027 Q1, 2027-03 or a name'),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      SmallButton('Cancel', onPressed: _cancel),
      SmallButton('Plan', primary: true, onPressed: _submit),
    ],
  );
}
