import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../local/ignore_rules.dart';
import '../state/add_ignore.dart';
import '../state/ignore_choice.dart';
import '../state/session.dart';
import 'error_view.dart';
import 'nav_keys.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ask how to ignore the highlighted rows, then write the rules. Only a session without a local
/// repository (or with nothing highlighted) gets a notice instead of the dialog; a failed write
/// comes back as the action's usual notice.
Future<void> showIgnoreDialog(BuildContext context, AddIgnoreState add) async {
  final choice = await IgnoreChoice.forSelection(add);
  if (!context.mounted) return;
  if (choice == null) return showActionError(context, 'ignore needs a local repository and a highlighted row');
  final go = await showDialog<bool>(context: context, builder: (_) => IgnoreDialog(choice: choice));
  if (go != true) return;
  final result = await choice.apply();
  if (!context.mounted) return;
  if (result.error != null) return showActionError(context, result.error);
  final effect = add.lastIgnoreEffect?.message;
  if (effect != null) SessionScope.maybeRead(context)?.notices.show(effect, failure: false);
}

/// The scope words, as in Purrage.
String scopeLabel(IgnoreScope s) => switch (s) {
  IgnoreScope.file => 'this file',
  IgnoreScope.extension => 'this extension',
  IgnoreScope.folder => 'this folder',
};

/// The Ignore dialog, ported from Purrage: how wide the rule is (the scope), which file it goes
/// into (where), and the exact lines it will write before they are written.
///
/// Complete by keys: `1` `2` `3` (or `f` `x` `d`) pick the scope, `j` / `k` or the arrows move through
/// the targets, Enter writes, Esc cancels.
class IgnoreDialog extends StatefulWidget {
  const IgnoreDialog({super.key, required this.choice});

  final IgnoreChoice choice;

  @override
  State<IgnoreDialog> createState() => _IgnoreDialogState();
}

class _IgnoreDialogState extends State<IgnoreDialog> {
  final focus = FocusNode(debugLabel: 'ignore dialog');

  IgnoreChoice get choice => widget.choice;

  static const _scopeKeys = {'1': 0, 'f': 0, '2': 1, 'x': 1, '3': 2, 'd': 2};

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  /// Enter and the Ignore button: close with a yes, unless nothing would be written.
  void _write() {
    if (choice.problem == null) Navigator.pop(context, true);
  }

  void _cancel() => Navigator.pop(context, false);

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _write();
      return KeyEventResult.handled;
    }
    final scope = _scopeKeys[e.character?.toLowerCase()];
    if (scope != null) {
      choice.setScope(IgnoreScope.values[scope]);
      return KeyEventResult.handled;
    }
    final nav = navKey(e);
    if (nav == null || !nav.vertical) return KeyEventResult.ignored;
    choice.stepTarget(nav.delta);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    autofocus: true,
    onKeyEvent: _onKey,
    child: ListenableBuilder(
      listenable: choice,
      builder: (context, _) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_title(), style: T.title),
        content: SizedBox(width: 520, child: _Body(choice: choice)),
        actions: [_Buttons(summary: choice.summary, canWrite: choice.problem == null, onCancel: _cancel, onWrite: _write)],
      ),
    ),
  );

  String _title() => choice.paths.length == 1 ? 'Ignore ${choice.paths.single}' : 'Ignore ${choice.paths.length} files';
}

class _Buttons extends StatelessWidget {
  const _Buttons({required this.summary, required this.canWrite, required this.onCancel, required this.onWrite});

  final String summary;
  final bool canWrite;
  final VoidCallback onCancel, onWrite;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Tooltip(message: 'Close without writing (Esc)', child: SmallButton('Cancel', onPressed: onCancel)),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Write $summary (Enter)',
          child: SmallButton('Ignore', primary: true, onPressed: canWrite ? onWrite : null),
        ),
      ],
    ),
  );
}

/// Scope, targets and preview, top to bottom.
class _Body extends StatelessWidget {
  const _Body({required this.choice});

  final IgnoreChoice choice;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Scope  (1 2 3, or f x d)', style: T.small),
        const SizedBox(height: 4),
        _ScopeChips(current: choice.scope, onPick: choice.setScope),
        const SizedBox(height: 12),
        const Text('Where  (j / k)', style: T.small),
        const SizedBox(height: 4),
        for (final (i, t) in choice.targets.indexed)
          _TargetTile(target: t, chosen: i == choice.targetIndex, onPick: () => choice.setTarget(i)),
        const SizedBox(height: 12),
        _Preview(choice: choice),
      ],
    ),
  );
}

class _ScopeChips extends StatelessWidget {
  const _ScopeChips({required this.current, required this.onPick});

  final IgnoreScope current;
  final ValueChanged<IgnoreScope> onPick;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final (i, s) in IgnoreScope.values.indexed)
        _ScopeChip(label: scopeLabel(s), index: i + 1, chosen: s == current, onTap: () => onPick(s)),
    ],
  );
}

/// One scope: a pill, filled with the accent while chosen.
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.index, required this.chosen, required this.onTap});

  final String label;
  final int index;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Scope: $label ($index)',
    child: Material(
      color: chosen ? C.accent : C.surface2,
      shape: StadiumBorder(side: BorderSide(color: chosen ? C.accent : C.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(label, style: T.body.copyWith(color: chosen ? C.bg : C.text)),
        ),
      ),
    ),
  );
}

/// One file a rule can go into: its name, its path, and a check while chosen.
class _TargetTile extends StatelessWidget {
  const _TargetTile({required this.target, required this.chosen, required this.onPick});

  final IgnoreTarget target;
  final bool chosen;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Write the rule to ${target.path}',
    child: HoverRow(
      key: ValueKey('ignore-target-${target.path}'),
      onTap: onPick,
      selected: chosen,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Expanded(child: _TargetText(target: target)),
          if (chosen) const Icon(Icons.check, size: 16, color: C.accent),
        ],
      ),
    ),
  );
}

/// One target's text: its name, its path, and — when the file is not there yet — that it will be made.
class _TargetText extends StatelessWidget {
  const _TargetText({required this.target});

  final IgnoreTarget target;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(IgnoreChoice.targetLabel(target), style: T.body),
      Text(target.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
      if (!target.exists) Text('does not exist yet: writing a rule creates it', style: T.tiny.copyWith(color: C.faint)),
    ],
  );
}

/// The lines about to be written, each once, and what would not be.
class _Preview extends StatelessWidget {
  const _Preview({required this.choice});

  final IgnoreChoice choice;

  List<String> get _lines {
    final rules = choice.patterns;
    return [
      ...rules.take(8),
      if (rules.length > 8) '… ${rules.length - 8} more',
      for (final name in choice.missing) '$name: no rule for this scope',
    ];
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: C.bg, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(6)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(choice.summary, style: T.small),
        const SizedBox(height: 4),
        for (final line in _lines) SelectableText(line, style: T.code),
      ],
    ),
  );
}
