import 'package:material_ui/material_ui.dart';

import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';

/// The milestones a task or a proposal can be planned for, by date: the milestone files not yet
/// completed, and the names tasks and proposals use without a file ('Next' is not one: it is
/// where the unplanned open changes go).
List<String> milestoneChoices(Workspace ws) => [for (final m in ws.milestones) if (!m.completed) m.name];

/// Makes a new milestone (a Backlog.md milestone file) before a task is planned for it.
typedef MilestoneCreate = void Function(String name, DateTime? due);

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

/// What a pick means: a milestone name, '' for none, or null (cancelled, or the new milestone
/// dialog was closed). A new one is made with [create] first (not awaited: it is in memory at
/// once, so the plan that follows finds it).
Future<String?> _resolve(BuildContext context, String? picked, MilestoneCreate? create) async {
  if (picked != _newMilestone) return picked;
  final m = await showDialog<NewMilestone>(context: context, builder: (_) => const MilestoneNameDialog());
  if (m == null) return null;
  create?.call(m.name, m.due);
  return m.name;
}

/// The Milestone property of a task or a change: shows the planned milestone, a click picks
/// another one, none, or a new one.
class MilestoneMenu extends StatelessWidget {
  const MilestoneMenu({super.key, required this.value, required this.choices, required this.tip, required this.onPick, this.onCreate});

  final String value;
  final List<String> choices;
  final String tip;
  final ValueChanged<String> onPick;
  final MilestoneCreate? onCreate;

  Future<void> _picked(BuildContext context, String v) async {
    final name = await _resolve(context, v, onCreate);
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
Future<String?> showMoveToMenu(
  BuildContext context,
  Offset at, {
  required List<String> choices,
  required String current,
  MilestoneCreate? onCreate,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final picked = await showMenu<String>(
    context: context,
    color: C.surface2,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: _entries(choices, current, prefix: 'Move to '),
  );
  if (picked == null || !context.mounted) return null;
  return _resolve(context, picked, onCreate);
}

/// What the new milestone dialog returns: a name and an optional due date.
typedef NewMilestone = ({String name, DateTime? due});

/// Asks for a new milestone: its name (`2027 Q1`, `2027-03`, `v1 launch`) and, optionally, its due
/// date (YYYY-MM-DD). It becomes a Backlog.md milestone file.
class MilestoneNameDialog extends StatefulWidget {
  const MilestoneNameDialog({super.key});

  @override
  State<MilestoneNameDialog> createState() => _MilestoneNameDialogState();
}

class _MilestoneNameDialogState extends State<MilestoneNameDialog> {
  final _name = TextEditingController();
  final _due = TextEditingController();
  bool _badDate = false;

  @override
  void dispose() {
    _name.dispose();
    _due.dispose();
    super.dispose();
  }

  /// The due date typed, null when empty; a text that is no date keeps the dialog open.
  (bool, DateTime?) _dueDate() {
    final t = _due.text.trim();
    if (t.isEmpty) return (true, null);
    final d = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t) ? DateTime.tryParse(t) : null;
    return (d != null, d);
  }

  void _submit() {
    final n = _name.text.trim();
    final (ok, due) = _dueDate();
    setState(() => _badDate = !ok);
    if (n.isNotEmpty && ok) Navigator.of(context).pop((name: n, due: due));
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: C.surface,
    title: Text('New milestone', style: T.title),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_name, '2027 Q1, 2027-03 or a name', autofocus: true),
          const SizedBox(height: 10),
          _field(_due, 'Due date, YYYY-MM-DD (optional)', error: _badDate ? 'Not a date: YYYY-MM-DD' : null),
        ],
      ),
    ),
    actions: [
      SmallButton('Cancel', onPressed: _cancel),
      SmallButton('Plan', primary: true, onPressed: _submit),
    ],
  );

  Widget _field(TextEditingController c, String hint, {bool autofocus = false, String? error}) => TextField(
    controller: c,
    autofocus: autofocus,
    style: T.body,
    decoration: InputDecoration(hintText: hint, errorText: error),
    onSubmitted: (_) => _submit(),
  );
}
