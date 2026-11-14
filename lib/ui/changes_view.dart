import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../backend/models.dart';
import '../state/changes.dart';
import '../state/list_pair.dart';
import '../state/session.dart';
import 'confirm_dialog.dart';
import 'diff_view.dart';
import 'error_view.dart';
import 'file_tree.dart';
import 'key_sequence.dart';
import 'nav_keys.dart';
import 'list_pair_view.dart';
import 'resizable_pane.dart';
import 'theme.dart';
import 'widgets.dart';

/// Working tree vs HEAD: staged and unstaged files, the selected diff with hunk buttons, and a
/// commit box. Editing happens in Neovim; clicking a line opens it there.
///
/// Page: owns the [ChangesState] and turns user events into its actions; the parts below only
/// show values and call back.
class ChangesView extends StatefulWidget {
  const ChangesView({super.key, this.onRail});

  /// Gives the keyboard to the mode rail (Left from the file lists, Tab round the cycle).
  final VoidCallback? onRail;

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
    'gg': () => st.moveSelection(-_far),
    'G': () => st.moveSelection(_far),
    ']c': () => st.moveHunk(1),
    '[c': () => st.moveHunk(-1),
    '-': _toggleCurrent,
    ' ': _stageCurrent,
    'u': _unstageCurrent,
    'X': _discardCurrent,
    'cc': _messageFocus.requestFocus,
    'o': _openCurrent,
    'v': () => st.toggleLayout(),
    'zw': () => st.toggleWrap(),
    'zR': () => st.expandAllDirs(),
    'zM': () => st.collapseAllDirs(),
    '{': () => st.jump(-1),
    '}': () => st.jump(1),
  });

  ChangesState get st => _state!;

  /// For the debug bar: the active pane's name (`ChangesPane`), or null before the state exists.
  String? get paneName => _state?.pane.name;

  /// For the debug bar.
  List<String> get debugInfo => _state == null
      ? const []
      : [
          'File: ${st.selected ?? '-'} (${st.selectedStaged ? 'staged' : 'unstaged'})',
          'Hunk: ${st.hunk < 0 ? '-' : st.hunk + 1}',
        ];

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

  /// Up / Down; past the last file of CHANGES the commit message gets the keyboard.
  void _move(int delta, {bool big = false}) {
    if (st.moveCursor(delta, big: big)) _messageFocus.requestFocus();
  }

  /// Tab / Shift+Tab: STAGED, CHANGES, the commit message, the diff, and round again.
  void _navigate(NavKey k) {
    switch (k.dir) {
      case NavDir.up || NavDir.down:
        _move(k.delta, big: k.big);
      case NavDir.left:
        _left();
      case NavDir.right:
        st.movePane(1);
    }
  }

  /// Left: from the diff back to its list; from a list (nothing is to its left) to the rail.
  void _left() => st.pane == ChangesPane.diff ? st.movePane(-1) : widget.onRail?.call();

  /// Tab from the rail: the first stop of the cycle (the first list, else the message), or with
  /// Shift+Tab the last (the diff).
  void enterFromRail({required bool forward}) {
    final lists = st.panes.where((p) => p != ChangesPane.diff).toList();
    if (!forward) {
      st.goTo(ChangesPane.diff);
      focus.requestFocus();
    } else if (lists.isEmpty) {
      _messageFocus.requestFocus();
    } else {
      st.goTo(lists.first);
      focus.requestFocus();
    }
  }

  /// Ctrl+arrow, sent by the shell: the pane in that direction.
  void ctrlArrow({required bool vertical, required int dir}) {
    if (vertical) {
      st.vertical(dir: dir, fromMessage: _messageFocus.hasFocus) ? _messageFocus.requestFocus() : focus.requestFocus();
    } else if (dir < 0) {
      _left();
    } else {
      st.movePane(1);
      focus.requestFocus();
    }
  }

  void _tab({required int delta}) {
    if (st.tabLeaves(fromMessage: _messageFocus.hasFocus, delta: delta)) return widget.onRail?.call();
    final to = st.tabFrom(fromMessage: _messageFocus.hasFocus, delta: delta);
    to == null ? _messageFocus.requestFocus() : focus.requestFocus();
  }

  void _tabFromMessage() => _tab(delta: 1);

  void _shiftTabFromMessage() => _tab(delta: -1);

  // Keys: Space (stage), j/k, arrows, Left/Right, gg/G, ]c/[c, -, s, u, X, cc, o, zR/zM; Tab and Shift+Tab cycle
  // the panes and the commit message.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (_messageFocus.hasFocus || hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final action = switch (e.logicalKey) {
      LogicalKeyboardKey.tab => () => _tab(delta: hw.isShiftPressed ? -1 : 1),
      _ => null,
    };
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    // The arrows, hjkl and wasd are one set of keys (see nav_keys.dart); a pending `z` or `g`
    // owns the next key (zw).
    final nav = _keys.pending ? null : navKey(e);
    if (nav != null) {
      _navigate(nav);
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
          ResizablePane(autoWidth: _autoWidth(), minWidth: _minSidebar, child: _sidebar()),
          Expanded(child: _main()),
        ],
      ),
    ),
  );

  static const _minSidebar = 160.0, _maxSidebar = 384.0; // 320 before: half, 120%

  /// The narrowest sidebar that shows every file and folder in full, plus the branch title and
  /// the commit box's hint.
  double _autoWidth() {
    final lists = [
      for (final (i, files) in [st.staged, st.unstaged].indexed)
        ...fileTreeWidths(
          [for (final f in files) TreeFile(path: f.path, status: '')],
          st.collapsedDirs[i],
          trailing: 16,
        ),
    ];
    final branch = 12 + 20 + textWidth(st.status?.branch ?? 'Changes', T.body);
    final headers = [
      for (final (title, n, all) in [('STAGED', st.staged.length, 'Unstage all'), ('CHANGES', st.unstaged.length, 'Stage all')])
        headerWidth(title, '$n', actions: 2, textActions: n == 0 ? 0 : 8 + textWidth(all, const TextStyle(fontSize: 12))),
    ];
    final n = st.staged.length;
    final commit = 12 + 12 + 20 + textWidth('Commit $n file${n == 1 ? '' : 's'} to ${st.status?.branch ?? ''}', const TextStyle(fontSize: 12.5));
    return paneWidth([...lists, ...headers, branch, commit], least: _minSidebar, most: _maxSidebar);
  }

  Widget _sidebar() {
    final branch = st.status?.branch ?? '';
    final n = st.staged.length;
    return ChangesSidebar(
      branch: branch,
      sections: [
        FileSectionData('STAGED', st.staged, staged: true, collapsedDirs: st.collapsedDirs[0], active: st.pane == ChangesPane.staged, selectBottom: st.selectBottom[0]),
        FileSectionData('CHANGES', st.unstaged, staged: false, collapsedDirs: st.collapsedDirs[1], active: st.pane == ChangesPane.unstaged, selectBottom: st.selectBottom[1]),
      ],
      pair: st.lists,
      clean: st.status != null && st.status!.files.isEmpty,
      selected: st.selected,
      selectedStaged: st.selectedStaged,
      onSelect: (path, staged) => st.pick(path, staged: staged),
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
        onTab: _tabFromMessage,
        onShiftTab: _shiftTabFromMessage,
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
      sideBySide: st.layout == DiffLayout.sideBySide,
      wrap: st.wrap,
      scroll: st.diffScroll,
      onToggleWrap: st.toggleWrap,
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
Future<bool> confirmDiscard(BuildContext context, String what) =>
    confirm(context, title: 'Discard changes?', text: '$what\nThis can\'t be undone.', okLabel: 'Discard', danger: true);

// Organisms ---------------------------------------------------------------------------------------

/// One side of the working tree: its title, files and folded folders.
class FileSectionData {
  const FileSectionData(
    this.title,
    this.files, {
    required this.staged,
    this.collapsedDirs = const {},
    this.active = false,
    this.selectBottom,
  });

  final String title;
  final List<StatusFile> files;
  final bool staged;
  final Set<String> collapsedDirs;

  /// The keys act on this list.
  final bool active;

  /// Bumps when the keyboard enters the list from below (see [FileTree.selectBottom]).
  final Listenable? selectBottom;

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
    active: data.active,
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
    selectBottom: data.selectBottom,
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
    this.sideBySide = false,
    this.wrap = true,
    this.onToggleWrap,
    this.scroll,
  });

  final DiffFile file;
  final ScrollController? scroll;
  final bool sideBySide, wrap;
  final VoidCallback? onToggleWrap;
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
      scroll: scroll,
      sideBySide: sideBySide,
      wrap: wrap,
      onLine: onLine,
      headerActions: [
        if (onToggleWrap != null)
          IconToggle(icon: Icons.wrap_text, tip: 'Line wrapping (zw)', on: wrap, onTap: onToggleWrap!),
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
/// Ctrl+Enter in the message commits; Esc goes back to the file list; Tab goes on to the diff,
/// Shift+Tab back to CHANGES.
class CommitBox extends StatelessWidget {
  const CommitBox({
    super.key,
    required this.controller,
    required this.focus,
    required this.label,
    required this.enabled,
    required this.onCommit,
    required this.onLeave,
    required this.onTab,
    required this.onShiftTab,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String label;
  final bool enabled;
  final VoidCallback onCommit, onLeave, onTab, onShiftTab;

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
              const SingleActivator(LogicalKeyboardKey.tab): onTab,
              const SingleActivator(LogicalKeyboardKey.tab, shift: true): onShiftTab,
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
