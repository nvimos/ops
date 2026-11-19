import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../local/ignore_rules.dart';
import '../state/add_ignore.dart';
import '../state/ignore_choice.dart';
import 'error_view.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ask how to ignore the highlighted untracked rows, then write the rules. Errors come back as the
/// action's usual snackbar.
Future<void> showIgnoreDialog(BuildContext context, AddIgnoreState add) async {
  final choice = await IgnoreChoice.forSelection(add);
  if (!context.mounted) return;
  if (choice == null) return showActionError(context, 'select an untracked file in a local repository to ignore');
  final go = await showDialog<bool>(context: context, builder: (_) => IgnoreDialog(choice: choice));
  if (go != true) return;
  final result = await choice.apply();
  if (context.mounted) showActionError(context, result.error);
}

/// The modal: the scope of the rule, the file it goes into, and what it would write and cover.
/// Enter writes, Esc cancels.
class IgnoreDialog extends StatelessWidget {
  const IgnoreDialog({super.key, required this.choice});

  final IgnoreChoice choice;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter): () => _write(context),
    },
    child: Focus(
      autofocus: true,
      child: ListenableBuilder(
        listenable: choice,
        builder: (context, _) => AlertDialog(
          backgroundColor: C.surface,
          title: Text(_title(), style: T.title),
          content: SizedBox(width: 520, child: _Body(choice: choice)),
          actions: [
            SelectionContainer.disabled(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallButton('Cancel', onPressed: () => Navigator.pop(context, false)),
                  const SizedBox(width: 8),
                  SmallButton('Ignore', primary: true, onPressed: choice.problem == null ? () => _write(context) : null),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  String _title() => choice.paths.length == 1 ? 'Ignore ${choice.shortPath(choice.paths.single)}' : 'Ignore ${choice.paths.length} files';

  void _write(BuildContext context) {
    if (choice.problem == null) Navigator.pop(context, true);
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.choice});

  final IgnoreChoice choice;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('WHAT TO IGNORE', style: T.section),
        _Scopes(choice: choice),
        const SizedBox(height: 12),
        const Text('WHERE TO WRITE IT', style: T.section),
        _Targets(choice: choice),
        const SizedBox(height: 12),
        _Preview(choice: choice),
      ],
    ),
  );
}

class _Scopes extends StatelessWidget {
  const _Scopes({required this.choice});

  final IgnoreChoice choice;

  static const _labels = {
    IgnoreScope.file: ('This file', 'one rule for the path'),
    IgnoreScope.extension: ('Every file like it', 'one rule for the extension, e.g. *.log'),
    IgnoreScope.folder: ('Its folder', 'one rule for the folder the file is in'),
  };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final s in IgnoreScope.values)
        _Option(
          label: _labels[s]!.$1,
          hint: _labels[s]!.$2,
          on: choice.scope == s,
          onTap: () => choice.setScope(s),
        ),
    ],
  );
}

class _Targets extends StatelessWidget {
  const _Targets({required this.choice});

  final IgnoreChoice choice;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < choice.targets.length; i++)
        _Option(
          label: choice.targets[i].label,
          hint: choice.targets[i].isCommitted ? 'committed with the repository' : 'stays on this machine',
          on: choice.targetIndex == i,
          onTap: () => choice.setTarget(i),
        ),
    ],
  );
}

/// One choice of a group: a radio mark, its label and a hint.
class _Option extends StatelessWidget {
  const _Option({required this.label, required this.hint, required this.on, required this.onTap});

  final String label, hint;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: hint,
    child: HoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 15, color: on ? C.accent : C.muted),
          const SizedBox(width: 8),
          Text(label, style: T.body),
          const SizedBox(width: 8),
          Expanded(child: Text(hint, style: T.tiny, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}

/// What would be written, which rows it takes off the list, and what git already ignores.
class _Preview extends StatelessWidget {
  const _Preview({required this.choice});

  final IgnoreChoice choice;

  @override
  Widget build(BuildContext context) {
    final covered = choice.covered;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: C.bg, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (choice.problem != null) Text(choice.problem!, style: T.small.copyWith(color: C.yellow)),
          for (final p in choice.patterns) SelectableText('+ $p', style: T.code.copyWith(color: C.addSign)),
          if (covered.isNotEmpty) Text('takes ${covered.length} row${covered.length == 1 ? '' : 's'} off the list: ${_names(covered)}', style: T.small),
          for (final e in choice.already.entries) Text('${e.key}: already ignored by ${choice.labelOf(e.value)}', style: T.tiny),
        ],
      ),
    );
  }

  static String _names(List<String> paths) {
    final shown = paths.take(6).map((p) => p.split('/').last).join(', ');
    return paths.length > 6 ? '$shown, …' : shown;
  }
}
