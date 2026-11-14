import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'widgets.dart';

/// A question as a modal: a title, the text, Cancel and an action button. The title and the text
/// are selectable (one drag covers both); the buttons stay buttons. Pops true for the action,
/// false for Cancel. Every question modal uses this one.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({super.key, required this.title, required this.text, required this.okLabel, this.danger = false});

  final String title, text, okLabel;

  /// The action is destructive (shown in red).
  final bool danger;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: AlertDialog(
      backgroundColor: C.surface,
      title: Text(title, style: T.title),
      content: Text(text, style: T.body),
      actions: [
        SelectionContainer.disabled(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SmallButton('Cancel', onPressed: () => Navigator.pop(context, false)),
              const SizedBox(width: 8),
              SmallButton(okLabel, primary: !danger, danger: danger, onPressed: () => Navigator.pop(context, true)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Ask [title] with [text]; true when the user takes the action.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String text,
  required String okLabel,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => ConfirmDialog(title: title, text: text, okLabel: okLabel, danger: danger),
  );
  return ok == true;
}
