import 'package:material_ui/material_ui.dart';

import '../local/git_repo.dart' show IgnoreMatch;
import '../state/ignore_pane.dart';
import 'error_view.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Ignore pane: the ignore files around the row under the cursor, with the rule that matches it
/// marked. A rule can be deleted or moved one folder up. [IgnorePaneState] does the work.
class IgnorePane extends StatelessWidget {
  const IgnorePane({super.key, required this.state});

  final IgnorePaneState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(title: const Text('Ignore rules'), trailing: [if (state.loading) const Spinner()]),
        Expanded(child: _body(context)),
      ],
    ),
  );

  Widget _body(BuildContext context) {
    if (!state.available) return const Empty('Ignore rules need a local repository.');
    if (state.error != null) return ErrorPane(state.error!, onRetry: state.forget);
    final info = state.info;
    if (info == null) return Empty(state.path == null ? 'No file under the cursor.' : 'Looking up the rules…');
    return _Rules(state: state, info: info);
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.state, required this.info});

  final IgnorePaneState state;
  final IgnoreInfo info;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Text(info.path, style: T.body, overflow: TextOverflow.ellipsis),
      ),
      _Verdict(match: info.match),
      for (final f in info.files) _File(state: state, info: info, file: f),
    ],
  );
}

/// Which rule decides the path, or that none does.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.match});

  final IgnoreMatch? match;

  String get _text {
    final m = match;
    if (m == null) return 'No rule ignores it.';
    return 'Ignored by ${m.pattern} (${m.source.split(RegExp(r'[\\/]')).last}:${m.line})';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    child: Text(_text, style: T.small.copyWith(color: match == null ? C.muted : C.yellow)),
  );
}

class _File extends StatelessWidget {
  const _File({required this.state, required this.info, required this.file});

  final IgnorePaneState state;
  final IgnoreInfo info;
  final IgnoreFileView file;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
        child: Text(file.target.label.toUpperCase(), style: T.section, overflow: TextOverflow.ellipsis),
      ),
      if (file.lines.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(14, 0, 14, 4), child: Text('no rules', style: T.tiny)),
      for (final l in file.lines) _Rule(state: state, file: file, line: l, matched: info.isMatch(file, l)),
    ],
  );
}

/// One rule of an ignore file; the buttons show while the mouse is over it.
class _Rule extends StatelessWidget {
  const _Rule({required this.state, required this.file, required this.line, required this.matched});

  final IgnorePaneState state;
  final IgnoreFileView file;
  final IgnoreLine line;
  final bool matched;

  @override
  Widget build(BuildContext context) => HoverRow(
    selected: matched,
    pointer: false,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 28, child: Text('${line.number}', style: T.tiny)),
        Expanded(child: Text(line.text, style: T.code, overflow: TextOverflow.ellipsis)),
        _Buttons(state: state, file: file, line: line),
      ],
    ),
  );
}

class _Buttons extends StatelessWidget {
  const _Buttons({required this.state, required this.file, required this.line});

  final IgnorePaneState state;
  final IgnoreFileView file;
  final IgnoreLine line;

  @override
  Widget build(BuildContext context) {
    if (!RowHover.of(context)) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconAction(
          icon: Icons.arrow_upward,
          tooltip: 'Move the rule one folder up',
          onPressed: state.canMoveUp(line) ? () => state.ruleOneFolderUp(file, line) : null,
        ),
        IconAction(icon: Icons.delete_outline, tooltip: 'Delete this rule', onPressed: () => state.deleteRule(file, line), color: C.yellow),
      ],
    );
  }
}
