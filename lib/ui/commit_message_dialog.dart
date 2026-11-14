import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../state/commit_template.dart';
import 'theme.dart';
import 'widgets.dart';

/// The commit message in a large modal, as Neovim's `git commit` shows it: the message, then git's
/// commented instructions and file list. The comment lines are dropped from the result. Pops the
/// message (null for Cancel); Ctrl+Enter takes it, Esc cancels.
class CommitMessageDialog extends StatefulWidget {
  const CommitMessageDialog({super.key, required this.message, required this.template});

  final String message, template;

  @override
  State<CommitMessageDialog> createState() => _CommitMessageDialogState();
}

class _CommitMessageDialogState extends State<CommitMessageDialog> {
  late final _text = TextEditingController(text: '${widget.message}\n\n${widget.template}\n');
  final _focus = FocusNode(debugLabel: 'commit message dialog');

  @override
  void initState() {
    super.initState();
    // the caret starts at the end of the message, above the comments
    _text.selection = TextSelection.collapsed(offset: widget.message.length);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _accept() => Navigator.pop(context, stripCommitComments(_text.text));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      backgroundColor: C.surface,
      title: const Text('Commit message', style: T.title),
      content: SizedBox(
        width: (size.width * .6).clamp(360, 900),
        height: size.height * .6,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): _accept},
          child: TextField(
            controller: _text,
            focusNode: _focus,
            autofocus: true,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: T.code,
          ),
        ),
      ),
      actions: [
        SmallButton('Cancel', onPressed: () => Navigator.pop(context)),
        const SizedBox(width: 8),
        SmallButton('Use message  (Ctrl+Enter)', primary: true, onPressed: _accept),
      ],
    );
  }
}

/// Opens the dialog; the edited message without comment lines, or null when cancelled.
Future<String?> showCommitMessageDialog(BuildContext context, {required String message, required String template}) =>
    showDialog<String>(context: context, builder: (_) => CommitMessageDialog(message: message, template: template));
