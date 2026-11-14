import 'package:material_ui/material_ui.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import 'file_tree.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ask what to do before switching to [branch] with [files] changed. Null: Cancel (the default
/// button, so Enter and Space cancel; so does Esc); otherwise how to take the changes along.
Future<CheckoutHow?> askCheckout(BuildContext context, {required String branch, required List<StatusFile> files}) =>
    showDialog<CheckoutHow>(
      context: context,
      builder: (_) => CheckoutDialog(branch: branch, files: files),
    );

/// The modal before a checkout that would touch uncommitted changes: lists the files, offers
/// Cancel (focused), Stash and checkout, and Checkout and discard (red, never the default).
class CheckoutDialog extends StatelessWidget {
  const CheckoutDialog({super.key, required this.branch, required this.files});

  final String branch;
  final List<StatusFile> files;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: AlertDialog(
      backgroundColor: C.surface,
      title: Text('Switch to $branch?', style: T.title),
      content: _Body(files: files),
      actions: [
        SelectionContainer.disabled(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              SmallButton('Cancel', autofocus: true, onPressed: () => Navigator.pop(context)),
              SmallButton('Stash and checkout', onPressed: () => Navigator.pop(context, CheckoutHow.stash)),
              SmallButton('Checkout and discard', danger: true, onPressed: () => Navigator.pop(context, CheckoutHow.force)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.files});

  final List<StatusFile> files;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 420,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${files.length} file${files.length == 1 ? ' has' : 's have'} uncommitted changes that the checkout would overwrite:',
          style: T.body,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(shrinkWrap: true, children: [for (final f in files) _FileLine(f)]),
        ),
      ],
    ),
  );
}

class _FileLine extends StatelessWidget {
  const _FileLine(this.file);

  final StatusFile file;

  @override
  Widget build(BuildContext context) {
    final kind = file.index == 'A' ? 'added' : (file.worktree == 'D' || file.index == 'D' ? 'deleted' : 'modified');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          StatusMark(kind),
          const SizedBox(width: 8),
          Expanded(child: Text(file.path, style: T.body, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
