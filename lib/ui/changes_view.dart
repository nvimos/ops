import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../backend/backend.dart' show CheckoutHow;
import '../backend/models.dart';
import '../state/changes.dart';
import '../state/commit_template.dart';
import '../state/list_pair.dart';
import '../state/session.dart';
import 'checkout_dialog.dart';
import 'commit_message_dialog.dart';
import 'confirm_dialog.dart';
import 'diff_view.dart';
import 'error_view.dart';
import 'file_tree.dart';
import 'key_sequence.dart';
import 'nav_keys.dart';
import 'pr_view.dart' show RevPicker;
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
  final _branchFocus = FocusNode(debugLabel: 'branch switcher');
  final _openBranches = ValueNotifier<int>(0);
  static const _far = 1 << 20;
  late final _keys = KeySequence({
    'gg': () => st.moveSelection(-_far),
    'G': () => st.moveSelection(_far),
    ']c': () => st.moveHunk(1),
    '[c': () => st.moveHunk(-1),
    'gb': openBranchSwitcher,
    '-': _toggleCurrent,
    ' ': _stageCurrent,
    'u': _unstageCurrent,
    'X': _discardCurrent,
    'cc': _messageFocus.requestFocus,
    'o': _openCurrent,
    'v': () => st.toggleLayout(),
    'zw': () => st.toggleWrap(),
    'zh': () => st.toggleHunkHeaders(),
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
  void initState() {
    super.initState();
    _branchFocus.addListener(_onBranchFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state ??= ChangesState(SessionScope.read(context));
  }

  @override
  void dispose() {
    _keys.dispose();
    _branchFocus.removeListener(_onBranchFocus);
    focus.dispose();
    _messageFocus.dispose();
    _branchFocus.dispose();
    _openBranches.dispose();
    _state?.dispose();
    _message.dispose();
    super.dispose();
  }

  /// The branch field got or lost the keyboard (a click, a key, a pick): the active pane follows.
  void _onBranchFocus() {
    final s = _state;
    if (s == null) return;
    _branchFocus.hasFocus ? s.goTo(ChangesPane.branch) : s.leaveBranch();
  }

  /// The node that holds the keyboard for the active pane: the switcher field or the list node.
  void _focusPane() => (st.pane == ChangesPane.branch ? _branchFocus : focus).requestFocus();

  /// Shift+C: the keyboard goes to the branch switcher and its list of branches opens.
  void openBranchSwitcher() {
    st.goTo(ChangesPane.branch);
    _branchFocus.requestFocus();
    _openBranches.value++;
  }

  // Event handlers -------------------------------------------------------------------------------

  void _report(String? err) {
    if (mounted) showActionError(context, err);
  }

  Future<void> _moveAll(bool staged) async => _report(await st.moveAll(staged: staged));

  Future<void> _moveFile(String path, bool staged) async => _report(await st.moveFile(path, staged: staged));

  /// A branch picked in the switcher. Changes to tracked files would be overwritten: the modal
  /// lists them first, and Cancel (the default) leaves everything as it is.
  Future<void> _switchBranch(String branch) async {
    if (branch == st.status?.branch) return focus.requestFocus();
    final files = st.wipedByCheckout;
    CheckoutHow? how;
    if (files.isNotEmpty) {
      how = await askCheckout(context, branch: branch, files: files);
      if (how == null) return focus.requestFocus();
    }
    _report(await st.switchBranch(branch, how: how));
    if (mounted) focus.requestFocus();
  }

  Future<void> _moveDir(String dir, bool staged) async => _report(await st.moveDir(dir, staged: staged));

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

  /// The message in a large modal with git's commented instructions; its result replaces the field's text.
  Future<void> _expandMessage() async {
    final text = await showCommitMessageDialog(
      context,
      message: _message.text,
      template: gitCommitTemplate(st.status),
    );
    if (text != null) _message.text = text;
    _messageFocus.requestFocus();
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

  /// An arrow key that cannot move the caret (empty field, first line for Up, start of text for Left) steps out: up to the list
  /// above, left to the rail, right to the diff. Down has nowhere to go. True when it left.
  bool _leaveMessageAtEdge(NavDir dir) {
    switch (dir) {
      case NavDir.up:
        st.vertical(dir: -1, fromMessage: true);
        focus.requestFocus();
      case NavDir.left:
        widget.onRail?.call();
      case NavDir.right:
        st.movePane(1);
        focus.requestFocus();
      case NavDir.down:
        return false;
    }
    return true;
  }

  /// Up / Down; past the last file of CHANGES the commit message gets the keyboard.
  void _move(int delta, {bool big = false}) {
    st.moveCursor(delta, big: big) ? _messageFocus.requestFocus() : _focusPane();
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
    if (forward) {
      st.goTo(ChangesPane.branch);
    } else {
      st.goTo(ChangesPane.diff);
    }
    _focusPane();
  }

  /// Ctrl+arrow, sent by the shell: the pane in that direction.
  void ctrlArrow({required bool vertical, required int dir}) {
    if (vertical) {
      st.vertical(dir: dir, fromMessage: _messageFocus.hasFocus) ? _messageFocus.requestFocus() : _focusPane();
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
    to == null ? _messageFocus.requestFocus() : _focusPane();
  }

  void _tabFromMessage() => _tab(delta: 1);

  void _shiftTabFromMessage() => _tab(delta: -1);

  /// The branch field is a text field: plain keys are typing. Tab goes round, Down steps to the
  /// first list (when the drop-down has not taken it), Left at the start of the text to the rail.
  KeyEventResult _branchKey(KeyEvent e, HardwareKeyboard hw) {
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      _tab(delta: hw.isShiftPressed ? -1 : 1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowLeft && _caretAtStart()) {
      _left();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool _caretAtStart() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    final sel = ctx?.findAncestorStateOfType<EditableTextState>()?.textEditingValue.selection;
    return sel != null && sel.isCollapsed && sel.baseOffset <= 0;
  }

  // Keys: Space (stage), j/k, arrows, Left/Right, gg/G, ]c/[c, -, s, u, X, cc, o, zR/zM; Tab and Shift+Tab cycle
  // the panes and the commit message.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (_messageFocus.hasFocus || hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (_branchFocus.hasFocus) return _branchKey(e, hw);
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
    final branch = 12 + 80 + textWidth(st.status?.branch ?? 'Changes', T.body);
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
      branchPicker: BranchSwitcher(
        branch: branch,
        names: st.branchNames,
        focus: _branchFocus,
        next: focus,
        onPick: _switchBranch,
        openList: _openBranches,
      ),
      sections: [
        FileSectionData('STAGED', st.staged, staged: true, collapsedDirs: st.collapsedDirs[0], active: st.pane == ChangesPane.staged, selectBottom: st.selectBottom[0]),
        FileSectionData('CHANGES', st.unstaged, staged: false, collapsedDirs: st.collapsedDirs[1], active: st.pane == ChangesPane.unstaged, selectBottom: st.selectBottom[1]),
      ],
      pair: st.lists,
      clean: st.status != null && st.status!.files.isEmpty,
      selected: st.selected,
      selectedStaged: st.selectedStaged,
      onSelect: (path, staged) => st.pick(path, staged: staged),
      onStep: (delta, staged) => st.stepFile(delta, staged: staged),
      onMoveFile: _moveFile,
      onMoveDir: _moveDir,
      onMoveAll: _moveAll,
      onToggleList: st.toggleList,
      onDominant: st.makeDominant,
      onToggleDir: st.toggleDir,
      onFoldAll: st.toggleAllDirs,
      commitBox: CommitBox(
        controller: _message,
        focus: _messageFocus,
        onExpand: _expandMessage,
        label: 'Commit $n file${n == 1 ? '' : 's'} to $branch',
        enabled: n > 0 && !st.busy,
        onCommit: _commit,
        onLeave: _leaveMessage,
        onTab: _tabFromMessage,
        onShiftTab: _shiftTabFromMessage,
        onArrowAtEdge: _leaveMessageAtEdge,
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
      hunkHeaders: st.hunkHeaders,
      onToggleHunkHeaders: st.toggleHunkHeaders,
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
    required this.branchPicker,
    required this.sections,
    required this.pair,
    required this.clean,
    required this.selected,
    required this.selectedStaged,
    required this.onSelect,
    required this.onStep,
    required this.onMoveFile,
    required this.onMoveDir,
    required this.onMoveAll,
    required this.onToggleList,
    required this.onDominant,
    required this.onToggleDir,
    required this.onFoldAll,
    required this.commitBox,
  });

  final Widget branchPicker;
  final List<FileSectionData> sections;
  final ListPair pair;
  final bool clean;
  final String? selected;
  final bool selectedStaged;
  final void Function(String path, bool staged) onSelect;

  /// The wheel steps through the files of a list: [delta] is -1 or 1.
  final void Function(int delta, bool staged) onStep;
  final void Function(String path, bool staged) onMoveFile;
  final void Function(String dir, bool staged) onMoveDir;
  final void Function(bool staged) onMoveAll;
  final ValueChanged<int> onToggleList, onDominant, onFoldAll;
  final void Function(int list, String dir) onToggleDir;
  final Widget commitBox;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      branchPicker,
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
      onStep: (d) => onStep(d, s.staged),
      onMoveFile: (p) => onMoveFile(p, s.staged),
      onToggleDir: (d) => onToggleDir(i, d),
      onMoveDir: (d) => onMoveDir(d, s.staged),
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
    required this.onStep,
    required this.onMoveFile,
    this.onToggleDir,
    this.onMoveDir,
  });

  final FileSectionData data;
  final String? selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<int> onStep;
  final ValueChanged<String> onMoveFile;
  final ValueChanged<String>? onToggleDir, onMoveDir;

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
    onStep: onStep,
    collapsed: data.collapsedDirs,
    onToggleDir: onToggleDir,
    folderTrailing: onMoveDir == null
        ? null
        : (dir) => StageCheckbox(staged: data.staged, what: 'folder', onTap: () => onMoveDir!(dir)),
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
    this.hunkHeaders = true,
    this.onToggleHunkHeaders,
    this.scroll,
  });

  final DiffFile file;
  final ScrollController? scroll;
  final bool sideBySide, wrap, hunkHeaders;
  final VoidCallback? onToggleWrap, onToggleHunkHeaders;
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
      hunkHeaders: hunkHeaders,
      onSign: onMoveHunk,
      signTip: staged ? 'Unstage hunk' : 'Stage hunk',
      onLine: onLine,
      headerActions: [
        if (onToggleHunkHeaders != null)
          IconToggle(icon: Icons.tag, tip: 'Hunk headers (zh)', on: hunkHeaders, onTap: onToggleHunkHeaders!),
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

/// At the end of the commit message field: open it in a large modal, and clear it (only while
/// there is text).
class _FieldButtons extends StatelessWidget {
  const _FieldButtons({required this.controller, required this.focus, required this.onExpand});

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onExpand;

  void _clear() {
    controller.clear();
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldButton(icon: Icons.open_in_full, tip: 'Edit the message in a larger window', onTap: onExpand),
        if (controller.text.isNotEmpty) _FieldButton(icon: Icons.close, tip: 'Clear the message', onTap: _clear),
      ],
    ),
  );
}

class _FieldButton extends StatelessWidget {
  const _FieldButton({required this.icon, required this.tip, required this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 15, color: C.muted),
      ),
    ),
  );
}

/// Message field and the Commit button.
/// Ctrl+Enter in the message commits; Esc goes back to the file list; Tab goes on to the diff,
/// Shift+Tab back to CHANGES.
class CommitBox extends StatelessWidget {
  const CommitBox({
    super.key,
    required this.controller,
    required this.focus,
    required this.onExpand,
    required this.label,
    required this.enabled,
    required this.onCommit,
    required this.onLeave,
    required this.onTab,
    required this.onShiftTab,
    required this.onArrowAtEdge,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String label;
  final bool enabled;
  final VoidCallback onExpand, onCommit, onLeave, onTab, onShiftTab;

  /// An arrow key that has nowhere to go inside the field; returns true when it took the key.
  final bool Function(NavDir dir) onArrowAtEdge;

  /// Whether the caret is on the first visual line of the text.
  bool _onFirstLine() {
    final box = focus.context?.findAncestorStateOfType<EditableTextState>()?.renderEditable;
    final caret = controller.selection.extentOffset;
    return box == null || box.getLineAtOffset(TextPosition(offset: caret)).start == 0;
  }

  /// Whether an arrow in direction [dir] would not move the caret: the key steps out instead.
  bool _atEdge(NavDir dir) {
    final sel = controller.selection;
    if (controller.text.isEmpty) return true;
    if (!sel.isCollapsed) return false;
    return switch (dir) {
      NavDir.up => _onFirstLine(),
      NavDir.left => sel.baseOffset <= 0,
      _ => false,
    };
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final arrow =
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight;
    final nav = arrow ? navKey(e) : null; // letters type into the field
    if (nav == null || !_atEdge(nav.dir)) return KeyEventResult.ignored;
    return onArrowAtEdge(nav.dir) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

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
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: TextField(
                controller: controller,
                focusNode: focus,
                minLines: 2,
                maxLines: 6,
                style: T.body,
                decoration: InputDecoration(
                  hintText: 'Commit message  (cc, Ctrl+Enter commits)',
                  suffixIcon: _FieldButtons(controller: controller, focus: focus, onExpand: onExpand),
                ),
              ),
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

/// The branch switcher at the top of Changes: the current branch in a picker that lists the local
/// branches (the same field as the base and head of Pull request, but it only takes listed
/// branches, and a pick checks the branch out).
class BranchSwitcher extends StatelessWidget {
  const BranchSwitcher({
    super.key,
    required this.branch,
    required this.names,
    required this.focus,
    required this.next,
    required this.onPick,
    this.openList,
  });

  final String branch;
  final List<String> names;
  final FocusNode focus, next;
  final ValueChanged<String> onPick;
  final Listenable? openList;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
    child: RevPicker(value: branch, names: names, focus: focus, next: next, onPick: onPick, strict: true, openList: openList),
  );
}

/// The button at the end of a file or folder row: the word "add", which stages it; for a staged one
/// the checked box, which unstages it.
class StageCheckbox extends StatelessWidget {
  const StageCheckbox({super.key, required this.staged, required this.onTap, this.what = 'current file'});

  final bool staged;
  final VoidCallback onTap;

  /// What the click acts on, for the tooltip ("current file", "folder").
  final String what;

  @override
  Widget build(BuildContext context) {
    // The add button shows only while the mouse is over its row (always where there is no mouse);
    // the checked box of a staged item always shows, it is state. The space stays, so rows line up.
    if (!staged && !RowHover.of(context)) return const SizedBox(width: _width);
    return _button();
  }

  static const _width = 30.0;

  Widget _button() => Tooltip(
    message: staged ? 'Unstage $what' : 'Stage $what',
    child: InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: SizedBox(
        width: 30,
        child: Center(
          child: staged
              ? const Icon(Icons.check_box, size: 16, color: C.accent)
              : const Text('add', style: TextStyle(fontSize: 12, color: C.muted)),
        ),
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
