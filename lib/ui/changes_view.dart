import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import '../state/changes.dart';
import '../state/session.dart';
import 'diff_view.dart';
import 'file_tree.dart';
import 'theme.dart';
import 'widgets.dart';

/// Working tree vs HEAD: staged and unstaged files, the selected diff with hunk buttons, and a
/// commit box. Editing happens in Neovim; clicking a line opens it there.
class ChangesView extends StatefulWidget {
  const ChangesView({super.key});

  @override
  State<ChangesView> createState() => _ChangesViewState();
}

class _ChangesViewState extends State<ChangesView> {
  ChangesState? _state;
  final _message = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state ??= ChangesState(SessionScope.read(context));
  }

  @override
  void dispose() {
    _state?.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function(Backend b) action) async {
    final err = await _state!.act(action);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<bool> _confirm(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Discard changes?', style: T.title),
        content: Text('$what\nThis can\'t be undone.', style: T.body),
        actions: [
          SmallButton('Cancel', onPressed: () => Navigator.pop(c, false)),
          SmallButton('Discard', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final st = _state!;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => Row(children: [
        SizedBox(width: 320, child: _sidebar(st)),
        const VerticalDivider(width: 1),
        Expanded(child: _main(st)),
      ]),
    );
  }

  Widget _sidebar(ChangesState st) {
    String kind(StatusFile f) => f.conflicted
        ? 'conflicted'
        : f.untracked
            ? 'untracked'
            : switch (f.staged ? f.index : f.worktree) { 'A' => 'added', 'D' => 'deleted', 'R' => 'renamed', _ => 'modified' };
    Widget section(String title, List<StatusFile> files, bool staged) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Row(children: [
            Text(title, style: T.section),
            const SizedBox(width: 6),
            Text('${files.length}', style: T.tiny),
            const Spacer(),
            if (files.isNotEmpty)
              _LinkButton(staged ? 'Unstage all' : 'Stage all', () {
                _do((b) async {
                  for (final f in files) {
                    staged ? await b.unstage(f.path) : await b.stage(f.path);
                  }
                });
              }),
          ]),
        ),
        SizedBox(
          height: (files.length * 30.0 + 10).clamp(30, 260),
          child: FileTree(
            files: [
              for (final f in files)
                TreeFile(
                  path: f.path,
                  status: kind(f),
                  trailing: Tooltip(
                    message: staged ? 'Unstage' : 'Stage',
                    child: InkWell(
                      onTap: () => _do((b) => staged ? b.unstage(f.path) : b.stage(f.path)),
                      child: Icon(staged ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: staged ? C.accent : C.muted),
                    ),
                  ),
                ),
            ],
            selected: st.selectedStaged == staged ? st.selected : null,
            onSelect: (p) => st.select(p, staged: staged),
          ),
        ),
      ]);
    }

    final branch = st.status?.branch ?? '';
    final canCommit = st.staged.isNotEmpty && !st.busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaneHeader(title: Row(children: [
        const Icon(Icons.call_split, size: 14, color: C.muted),
        const SizedBox(width: 6),
        Text(branch.isEmpty ? 'Changes' : branch),
      ])),
      Expanded(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            section('STAGED', st.staged, true),
            section('CHANGES', st.unstaged, false),
            if (st.status != null && st.status!.files.isEmpty) const Empty('Working tree clean'),
          ]),
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _message,
            minLines: 2,
            maxLines: 6,
            style: T.body,
            decoration: const InputDecoration(hintText: 'Commit message'),
          ),
          const SizedBox(height: 8),
          SmallButton(
            'Commit ${st.staged.length} file${st.staged.length == 1 ? '' : 's'} to $branch',
            primary: true,
            onPressed: !canCommit
                ? null
                : () async {
                    final err = await st.commit(_message.text);
                    if (!mounted) return;
                    if (err == null) {
                      _message.clear();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
          ),
        ]),
      ),
    ]);
  }

  Widget _main(ChangesState st) {
    final f = st.diff;
    final path = st.selected;
    if (path == null) return const Empty('No changes. Edit in Neovim; files show up here as you save.');
    if (f == null) return const Empty('Loading…');
    final staged = st.selectedStaged;
    return DiffView(
      file: f,
      onLine: (line, isOld) {
        if (isOld) return;
        final s = SessionScope.read(context);
        s.run((b) => b.open(path, line));
      },
      headerActions: [
        if (!staged)
          SmallButton('Discard file', danger: true, onPressed: () async {
            if (await _confirm('All unstaged changes in $path.')) _do((b) => b.discard(path));
          }),
        const SizedBox(width: 6),
        SmallButton(staged ? 'Unstage file' : 'Stage file',
            onPressed: () => _do((b) => staged ? b.unstage(path) : b.stage(path))),
      ],
      hunkActions: (h) => [
        if (!staged)
          _LinkButton('Discard', () async {
            if (await _confirm('This hunk of $path.')) _do((b) => b.discardHunk(path, h));
          }, color: C.red),
        const SizedBox(width: 10),
        _LinkButton(staged ? 'Unstage hunk' : 'Stage hunk',
            () => _do((b) => staged ? b.unstageHunk(path, h) : b.stageHunk(path, h))),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton(this.label, this.onTap, {this.color = C.accent});

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(label, style: TextStyle(fontSize: 12, color: color)),
        ),
      );
}
