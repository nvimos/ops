import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/models.dart';
import '../state/changes.dart';
import '../state/list_pair.dart';
import '../state/session.dart';
import 'diff_view.dart';
import 'error_view.dart';
import 'file_tree.dart';
import 'key_sequence.dart';
import 'list_pair_view.dart';
import 'theme.dart';
import 'widgets.dart';

/// Working tree vs HEAD: staged and unstaged files, the selected diff with hunk buttons, and a
/// commit box. Editing happens in Neovim; clicking a line opens it there.
///
/// Page: owns the [ChangesState] and turns user events into its actions; the parts below only
/// show values and call back.
class ChangesView extends StatefulWidget {
  const ChangesView({super.key});

  @override
  State<ChangesView> createState() => ChangesViewState();
}

class ChangesViewState extends State<ChangesView> {
  ChangesState? _state;
  final _message = TextEditingController();

  /// The shell gives the keyboard here when the mode is shown.
  final focus = FocusNode(debugLabel: 'changes');
  final _messageFocus = FocusNode(debugLabel: 'commit message');
  static const _far = 1 << 20;
  late final _keys = KeySequence({
    'j': () => st.moveSelection(1),
    'k': () => st.moveSelection(-1),
    'gg': () => st.moveSelection(-_far),
    'G': () => st.moveSelection(_far),
    ']c': () => st.moveHunk(1),
    '[c': () => st.moveHunk(-1),
    '-': _toggleCurrent,
    's': _stageCurrent,
    'u': _unstageCurrent,
    'X': _discardCurrent,
    'cc': _messageFocus.requestFocus,
    'o': _openCurrent,
    'zR': () => st.expandAllDirs(),
    'zM': () => st.collapseAllDirs(),
  });

  ChangesState get st => _state!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state ??= ChangesState(SessionScope.read(context));
  }

  @override
  void dispose() {
    _keys.dispose();
    focus.dispose();
    _messageFocus.dispose();
    _state?.dispose();
    _message.dispose();
    super.dispose();
  }

  // Event handlers -------------------------------------------------------------------------------

  void _report(String? err) {
    if (mounted) showActionError(context, err);
  }

  Future<void> _moveAll(bool staged) async => _report(await st.moveAll(staged: staged));

  Future<void> _moveFile(String path, bool staged) async => _report(await st.moveFile(path, staged: staged));

  Future<void> _moveSelected() => _moveFile(st.selected!, st.selectedStaged);

  Future<void> _discardSelected() async {
    final path = st.selected!;
    if (await confirmDiscard(context, 'All unstaged changes in $path.')) _report(await st.discardFile(path));
  }

  Future<void> _moveHunk(Hunk h) async => _report(await st.toggleHunk(h));

  Future<void> _discardHunk(Hunk h) async {
    if (await confirmDiscard(context, 'This hunk of ${st.selected}.')) _report(await st.discardHunk(h));
  }

  Future<void> _openLine(int line, bool isOld) async => _report(await st.openLine(line, isOld: isOld));

  Future<void> _commit() async {
    if (st.staged.isEmpty || st.busy) return;
    final err = await st.commit(_message.text);
    if (err == null) _message.clear();
    _report(err);
  }

  Future<void> _toggleCurrent() async => _report(await st.toggleCurrent());

  Future<void> _stageCurrent() async => _report(await st.stageCurrent());

  Future<void> _unstageCurrent() async => _report(await st.unstageCurrent());

  /// X: discard the current hunk, or the whole file; unstaged changes only, after asking.
  Future<void> _discardCurrent() async {
    if (st.selected == null || st.selectedStaged) return;
    final h = st.currentHunk;
    h != null ? await _discardHunk(h) : await _discardSelected();
  }

  Future<void> _openCurrent() => _openLine(st.currentLine, false);

  void _leaveMessage() => focus.requestFocus();

  // Keys: j/k, gg/G, ]c/[c, -, s, u, X, cc, o, zR/zM; Tab goes to the commit message and back.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (_messageFocus.hasFocus || hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final action = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowDown => () => st.moveSelection(1),
      LogicalKeyboardKey.arrowUp => () => st.moveSelection(-1),
      LogicalKeyboardKey.tab => _messageFocus.requestFocus,
      _ => null,
    };
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    return _keys.press(e.character) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  // Layout -------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onKeyEvent: _onKey,
    child: ListenableBuilder(
      listenable: st,
      builder: (context, _) => Row(
        children: [
          SizedBox(width: 320, child: _sidebar()),
          const VerticalDivider(width: 1),
          Expanded(child: _main()),
        ],
      ),
    ),
  );

  Widget _sidebar() {
    final branch = st.status?.branch ?? '';
    final n = st.staged.length;
    return ChangesSidebar(
      branch: branch,
      sections: [
        FileSectionData('STAGED', st.staged, staged: true, collapsedDirs: st.collapsedDirs[0]),
        FileSectionData('CHANGES', st.unstaged, staged: false, collapsedDirs: st.collapsedDirs[1]),
      ],
      pair: st.lists,
      clean: st.status != null && st.status!.files.isEmpty,
      selected: st.selected,
      selectedStaged: st.selectedStaged,
      onSelect: (path, staged) => st.select(path, staged: staged),
      onMoveFile: _moveFile,
      onMoveAll: _moveAll,
      onToggleList: st.toggleList,
      onDominant: st.makeDominant,
      onToggleDir: st.toggleDir,
      onFoldAll: st.toggleAllDirs,
      commitBox: CommitBox(
        controller: _message,
        focus: _messageFocus,
        label: 'Commit $n file${n == 1 ? '' : 's'} to $branch',
        enabled: n > 0 && !st.busy,
        onCommit: _commit,
        onLeave: _leaveMessage,
      ),
    );
  }

  Widget _main() {
    final f = st.diff;
    if (st.error != null) return ErrorPane(st.error!, onRetry: st.refresh);
    if (st.selected == null) return const Empty('No changes. Edit in Neovim; files show up here as you save.');
    if (f == null) return const Empty('Loading…');
    return ChangesDiff(
      file: f,
      staged: st.selectedStaged,
      hunk: st.hunk,
      onLine: _openLine,
      onMoveFile: _moveSelected,
      onDiscardFile: _discardSelected,
      onMoveHunk: _moveHunk,
      onDiscardHunk: _discardHunk,
    );
  }
}

/// Ask before throwing work away.
Future<bool> confirmDiscard(BuildContext context, String what) async {
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

// Organisms ---------------------------------------------------------------------------------------

/// One side of the working tree: its title, files and folded folders.
class FileSectionData {
  const FileSectionData(this.title, this.files, {required this.staged, this.collapsedDirs = const {}});

  final String title;
  final List<StatusFile> files;
  final bool staged;
  final Set<String> collapsedDirs;

  /// How tall the list wants to be, for [pairHeights].
  ListSize get size {
    final rows = treeRows([for (final f in files) TreeFile(path: f.path, status: '')], collapsedDirs);
    return (rows: rows.length, row: 26, pad: 8);
  }
}

/// The left pane: branch, STAGED over CHANGES (each foldable, one with the most room, as in the
/// Pull request view), the commit box.
class ChangesSidebar extends StatelessWidget {
  const ChangesSidebar({
    super.key,
    required this.branch,
    required this.sections,
    required this.pair,
    required this.clean,
    required this.selected,
    required this.selectedStaged,
    required this.onSelect,
    required this.onMoveFile,
    required this.onMoveAll,
    required this.onToggleList,
    required this.onDominant,
    required this.onToggleDir,
    required this.onFoldAll,
    required this.commitBox,
  });

  final String branch;
  final List<FileSectionData> sections;
  final ListPair pair;
  final bool clean;
  final String? selected;
  final bool selectedStaged;
  final void Function(String path, bool staged) onSelect;
  final void Function(String path, bool staged) onMoveFile;
  final void Function(bool staged) onMoveAll;
  final ValueChanged<int> onToggleList, onDominant, onFoldAll;
  final void Function(int list, String dir) onToggleDir;
  final Widget commitBox;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PaneHeader(title: _BranchTitle(branch)),
      Expanded(
        child: ListPairColumn(
          pair: pair,
          sizes: [for (final s in sections) s.size],
          headers: [for (final (i, s) in sections.indexed) _header(i, s)],
          lists: [for (final (i, s) in sections.indexed) _list(i, s)],
        ),
      ),
      const Divider(height: 1),
      commitBox,
    ],
  );

  Widget _header(int i, FileSectionData s) => FileSectionHeader(
    data: s,
    collapsed: pair.collapsed[i],
    dominant: pair.dominant == i,
    onToggle: () => onToggleList(i),
    onDominant: () => onDominant(i),
    onFoldAll: () => onFoldAll(i),
    onMoveAll: () => onMoveAll(s.staged),
  );

  Widget _list(int i, FileSectionData s) {
    if (clean && !s.staged) return const Empty('Working tree clean');
    return FileSection(
      data: s,
      selected: selectedStaged == s.staged ? selected : null,
      onSelect: (p) => onSelect(p, s.staged),
      onMoveFile: (p) => onMoveFile(p, s.staged),
      onToggleDir: (d) => onToggleDir(i, d),
    );
  }
}

/// STAGED or CHANGES: chevron, count, "Stage all" / "Unstage all", fold all, most room.
class FileSectionHeader extends StatelessWidget {
  const FileSectionHeader({
    super.key,
    required this.data,
    required this.collapsed,
    required this.dominant,
    required this.onToggle,
    required this.onDominant,
    required this.onFoldAll,
    required this.onMoveAll,
  });

  final FileSectionData data;
  final bool collapsed, dominant;
  final VoidCallback onToggle, onDominant, onFoldAll, onMoveAll;

  @override
  Widget build(BuildContext context) => SectionTitle(
    title: data.title,
    count: '${data.files.length}',
    collapsed: collapsed,
    onTap: onToggle,
    actions: [
      if (data.files.isNotEmpty) LinkButton(data.staged ? 'Unstage all' : 'Stage all', onMoveAll),
      FoldAllButton(folded: data.collapsedDirs.isNotEmpty, onTap: onFoldAll),
      DominantButton(what: data.staged ? 'staged files' : 'changes', on: dominant, onTap: onDominant),
    ],
  );
}

/// The file tree of a STAGED or CHANGES list, with a stage checkbox per file.
class FileSection extends StatelessWidget {
  const FileSection({
    super.key,
    required this.data,
    required this.selected,
    required this.onSelect,
    required this.onMoveFile,
    this.onToggleDir,
  });

  final FileSectionData data;
  final String? selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onMoveFile;
  final ValueChanged<String>? onToggleDir;

  @override
  Widget build(BuildContext context) => FileTree(
    files: [
      for (final f in data.files)
        TreeFile(
          path: f.path,
          status: fileKind(f, staged: data.staged),
          trailing: StageCheckbox(staged: data.staged, onTap: () => onMoveFile(f.path)),
        ),
    ],
    selected: selected,
    onSelect: onSelect,
    collapsed: data.collapsedDirs,
    onToggleDir: onToggleDir,
  );
}

/// The selected file's diff with file and hunk actions; unstaged files can also be discarded.
class ChangesDiff extends StatelessWidget {
  const ChangesDiff({
    super.key,
    required this.file,
    required this.staged,
    required this.onLine,
    required this.onMoveFile,
    required this.onDiscardFile,
    required this.onMoveHunk,
    required this.onDiscardHunk,
    this.hunk = -1,
  });

  final DiffFile file;
  final bool staged;
  final int hunk;
  final void Function(int line, bool isOld) onLine;
  final VoidCallback onMoveFile;
  final VoidCallback onDiscardFile;
  final ValueChanged<Hunk> onMoveHunk;
  final ValueChanged<Hunk> onDiscardHunk;

  @override
  Widget build(BuildContext context) {
    final fileActions = [
      if (!staged) (label: 'Discard file', danger: true, onTap: onDiscardFile),
      (label: staged ? 'Unstage file' : 'Stage file', danger: false, onTap: onMoveFile),
    ];
    return DiffView(
      file: file,
      hunk: hunk,
      onLine: onLine,
      headerActions: [
        for (final a in fileActions)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: SmallButton(a.label, danger: a.danger, onPressed: a.onTap),
          ),
      ],
      hunkActions: (h) => [
        if (!staged) LinkButton('Discard', () => onDiscardHunk(h), color: C.red),
        const SizedBox(width: 10),
        LinkButton(staged ? 'Unstage hunk' : 'Stage hunk', () => onMoveHunk(h)),
      ],
    );
  }
}

/// Message field and the Commit button.
/// Ctrl+Enter in the message commits; Esc (or Tab) goes back to the file list.
class CommitBox extends StatelessWidget {
  const CommitBox({
    super.key,
    required this.controller,
    required this.focus,
    required this.label,
    required this.enabled,
    required this.onCommit,
    required this.onLeave,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String label;
  final bool enabled;
  final VoidCallback onCommit, onLeave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true): onCommit,
              const SingleActivator(LogicalKeyboardKey.escape): onLeave,
              const SingleActivator(LogicalKeyboardKey.tab): onLeave,
            },
            child: TextField(
              controller: controller,
              focusNode: focus,
              minLines: 2,
              maxLines: 6,
              style: T.body,
              decoration: const InputDecoration(hintText: 'Commit message  (cc, Ctrl+Enter commits)'),
            ),
          ),
          const SizedBox(height: 8),
          SmallButton(label, primary: true, onPressed: enabled ? onCommit : null),
        ],
      ),
    );
  }
}

// Molecules and atoms ------------------------------------------------------------------------------

class _BranchTitle extends StatelessWidget {
  const _BranchTitle(this.branch);

  final String branch;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.call_split, size: 14, color: C.muted),
      const SizedBox(width: 6),
      Text(branch.isEmpty ? 'Changes' : branch),
    ],
  );
}

/// The checkbox at the end of a file row: checked when staged.
class StageCheckbox extends StatelessWidget {
  const StageCheckbox({super.key, required this.staged, required this.onTap});

  final bool staged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: staged ? 'Unstage' : 'Stage',
    child: InkWell(
      onTap: onTap,
      child: Icon(
        staged ? Icons.check_box : Icons.check_box_outline_blank,
        size: 16,
        color: staged ? C.accent : C.muted,
      ),
    ),
  );
}

/// Text that acts like a link.
class LinkButton extends StatelessWidget {
  const LinkButton(this.label, this.onTap, {super.key, this.color = C.accent});

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
