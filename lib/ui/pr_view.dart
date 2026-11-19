import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../backend/models.dart';
import '../state/picker_focus.dart';
import '../state/pr.dart';
import '../state/session.dart';
import '../tasks/model.dart';
import '../tasks/workspace.dart';
import 'confirm_dialog.dart';
import 'conflict_view.dart';
import 'diff_view.dart';
import 'error_view.dart';
import 'file_tree.dart';
import 'list_pair_view.dart';
import 'resizable_pane.dart';
import 'reveal.dart';
import 'tasks/review_panel.dart';
import 'theme.dart';
import 'view_bar.dart';
import 'wheel_mode.dart';
import 'widgets.dart';

/// Two revisions as a pull request: pickers, changed files and commits on the left, the diff on
/// the right, like GitHub's "Files changed" tab.
///
/// Page: owns the event handlers; [PrState] does the work, the parts below only show it.
class PrView extends StatefulWidget {
  const PrView({super.key, this.state, this.reviewing, this.workspace, this.onStopReview, this.onOpenTask});

  /// Shared state (the Tasks mode opens a review for a branch); created here when null.
  final PrState? state;

  /// The task being reviewed (from the Tasks mode), and the workspace it lives in.
  final Task? reviewing;
  final Workspace? workspace;
  final VoidCallback? onStopReview;
  final void Function(String id)? onOpenTask;

  @override
  State<PrView> createState() => _PrViewState();
}

class _PrViewState extends State<PrView> {
  PrState? _own;
  PrState get _pr => widget.state ?? _own!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.state == null) _own ??= PrState(SessionScope.read(context));
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _report(String? err) {
    if (mounted) showActionError(context, err);
  }

  Future<void> _jump(int line, bool isOld) async => _report(await _pr.openInNeovim(line, isOld: isOld));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pr,
      builder: (context, _) {
        final t = widget.reviewing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t != null) _ReviewBanner(task: t, onOpenTask: widget.onOpenTask, onDone: widget.onStopReview),
            ViewBar(layout: _pr.layout, mergeOpen: _pr.conflicts.current != null, onLayout: _pr.setLayout),
            Expanded(child: _columns(t)),
          ],
        );
      },
    );
  }

  static const _minSidebar = 150.0, _maxSidebar = 360.0; // 300 before: half, 120%

  /// The narrowest sidebar that shows every file, folder, commit and picker value in full.
  double _autoWidth() {
    final files = [
      for (final f in _pr.diff?.files ?? const <DiffFile>[])
        TreeFile(path: f.path, status: f.status, additions: f.additions, deletions: f.deletions),
    ];
    final adds = files.fold<int>(0, (n, f) => n + f.additions);
    final dels = files.fold<int>(0, (n, f) => n + f.deletions);
    final pickers = [
      for (final n in [_pr.base, _pr.head]) 24 + 50 + textWidth(n ?? '', T.body),
    ];
    return paneWidth(
      [
        ...fileTreeWidths(files, _pr.collapsedDirs),
        ...commitWidths(_pr.commits),
        headerWidth('FILES CHANGED', '${files.length}', extra: '+$adds −$dels', actions: 2),
        headerWidth('COMMITS', '${_pr.commits.length}', actions: 1),
        ...pickers,
      ],
      least: _minSidebar,
      most: _maxSidebar,
    );
  }

  Widget _columns(Task? t) => Row(
    children: [
      ResizablePane(autoWidth: _autoWidth(), minWidth: _minSidebar, child: _Sidebar(pr: _pr)),
      Expanded(child: _PrMain(pr: _pr, onLine: _pr.session.hasEditor ? _jump : null)),
      if (t != null && widget.workspace != null) ...[
        const VerticalDivider(width: 1),
        SizedBox(
          width: 300,
          child: ReviewPanel(ws: widget.workspace!, taskId: t.id, onOpenTask: widget.onOpenTask, onError: _report),
        ),
      ],
    ],
  );
}

// Organisms ---------------------------------------------------------------------------------------

/// The diff of the selected file, or what to do first.
class _PrMain extends StatelessWidget {
  const _PrMain({required this.pr, this.onLine});

  final PrState pr;
  final OnDiffLine? onLine;

  @override
  Widget build(BuildContext context) {
    final f = pr.selectedFile;
    if (pr.layout == DiffLayout.conflict) return ConflictPane(controller: pr.conflicts);
    if (pr.error != null) return ErrorPane(pr.error!, onRetry: pr.refresh);
    if (pr.base == pr.head) return const Empty('Pick two different revisions.');
    if (pr.diff == null) return Empty(pr.loading ? 'Loading…' : 'No diff.');
    if (pr.diff!.files.isEmpty) return const Empty('No changes between these revisions.');
    if (f == null) return const Empty('Pick a file.');
    return Listener(
      onPointerDown: (_) => pr.clickPane(PrPane.diff),
      child: _diff(f),
    );
  }

  Widget _diff(DiffFile f) {
    return DiffView(
      file: f,
      sideBySide: pr.layout == DiffLayout.sideBySide,
      wrap: pr.wrap,
      hunkHeaders: pr.hunkHeaders,
      hunk: pr.hunk,
      scroll: pr.diffScroll,
      onLine: onLine,
      headerActions: [
        IconToggle(icon: Icons.tag, tip: 'Hunk headers (zh)', on: pr.hunkHeaders, onTap: pr.toggleHunkHeaders),
        IconToggle(icon: Icons.wrap_text, tip: 'Line wrapping (zw)', on: pr.wrap, onTap: pr.toggleWrap),
      ],
    );
  }
}

/// Across the top while reviewing a task's branch: the task and "Done reviewing".
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.task, required this.onOpenTask, required this.onDone});

  final Task task;
  final void Function(String id)? onOpenTask;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => Container(
    color: C.surface2,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      children: [
        const Icon(Icons.task_alt, size: 15, color: C.accent),
        const SizedBox(width: 8),
        InkWell(
          onTap: onOpenTask == null ? null : () => onOpenTask!(task.id),
          child: Text(task.id, style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.accent)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(task.title, style: T.body, overflow: TextOverflow.ellipsis)),
        SmallButton('Done reviewing', onPressed: onDone),
      ],
    ),
  );
}

/// The left pane: pickers on top, then the files and commits lists.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PrPickers(pr: pr),
      const Divider(height: 1),
      Expanded(child: _Lists(pr: pr)),
    ],
  );
}

/// The line between the pickers: Swap in the label column, between the "base" and "head" labels,
/// and the merge actions in line with the fields (more can follow).
class ActionsLine extends StatelessWidget {
  const ActionsLine({super.key, required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: RevPicker.labelWidth,
        child: Center(
          child: IconButton(
            tooltip: 'Swap (gs)',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: pr.swap,
            icon: const Icon(Icons.swap_vert, color: C.muted),
          ),
        ),
      ),
      Tooltip(
        message: 'Merge head into base: a merge commit on base, local only',
        child: SmallButton('merge', icon: Icons.merge, onPressed: pr.canMerge ? () => mergeBranches(context, pr) : null),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: 'Rebase head onto base: head\'s commits replayed on top of base, local only',
        child: SmallButton('rebase', icon: Icons.low_priority, onPressed: pr.canRebase ? () => rebaseBranch(context, pr) : null),
      ),
    ],
  );
}

/// Rebase head onto base, no question (a conflict is undone); always say what happened.
Future<void> rebaseBranch(BuildContext context, PrState pr) async {
  final (base, head) = (pr.base!, pr.head!);
  final r = await pr.rebase();
  if (!context.mounted) return;
  if (r.error != null) return showActionError(context, r.error!);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(r.upToDate ? '$head is already on top of $base' : 'Rebased $head onto $base'),
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Merge head into base at once; say what happened. When base moved meanwhile, nothing was saved:
/// offer to rebase head onto the new base, then merge it (the history stays one straight line).
Future<void> mergeBranches(BuildContext context, PrState pr) async {
  final (base, head) = (pr.base!, pr.head!);
  final r = await pr.merge();
  if (!context.mounted) return;
  final err = r.error;
  if (err == null) {
    if (r.note != null) _noteMerged(context, r.note!);
    return;
  }
  if (!err.contains(baseMovedText)) return showActionError(context, err);
  final ok = await confirm(
    context,
    title: 'Rebase $head onto $base, then merge?',
    text:
        '$base moved while the merge ran, so nothing was saved.\n'
        'The rebase checks $head out: the folder moves to it. The branch you were on is left as it is.',
    okLabel: 'Rebase and merge',
  );
  if (!ok || !context.mounted) return;
  final rb = await pr.rebase();
  if (!context.mounted) return;
  if (rb.error != null) return showActionError(context, rb.error!);
  final again = await pr.merge();
  if (!context.mounted) return;
  if (again.error != null) return showActionError(context, again.error);
  _noteMerged(context, 'Rebased $head onto $base and merged');
}

/// The text the backend's merge error carries when base moved during the merge (git.lua, move_base).
const baseMovedText = 'base moved during the merge';

void _noteMerged(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

class PrPickers extends StatelessWidget {
  const PrPickers({super.key, required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RevPicker(
          label: 'base',
          value: pr.base,
          names: pr.baseNames,
          focus: pr.baseFocus,
          next: pr.headFocus,
          onPick: pr.pickBase,
        ),
        ActionsLine(pr: pr),
        RevPicker(
          label: 'head',
          value: pr.head,
          names: pr.headNames,
          focus: pr.headFocus,
          onPick: pr.pickHead,
          openList: pr.openHead,
        ),
      ],
    ),
  );
}

/// Row heights the left pane works with.
const _fileRow = 26.0, _commitRow = 24.0;

/// How tall FILES CHANGED and COMMITS want to be, for [pairHeights].
List<ListSize> leftPaneSizes(PrState pr) {
  final files = pr.diff?.files ?? const <DiffFile>[];
  final rows = treeRows([for (final f in files) TreeFile(path: f.path, status: f.status)], pr.collapsedDirs);
  return [(rows: rows.length, row: _fileRow, pad: 8), (rows: pr.commits.length, row: _commitRow, pad: 0)];
}

/// FILES CHANGED above COMMITS, each foldable, one of them with the most room.
class _Lists extends StatelessWidget {
  const _Lists({required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) => ListPairColumn(
    pair: pr.lists,
    sizes: leftPaneSizes(pr),
    banner: pr.narrowed == null ? null : _NarrowBanner(commit: pr.narrowed!, onAll: pr.showAllCommits),
    headers: [_FilesHeader(pr: pr), _CommitsHeader(pr: pr)],
    lists: [_Files(pr: pr), _CommitList(pr: pr)],
  );
}

class _FilesHeader extends StatelessWidget {
  const _FilesHeader({required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) {
    final files = pr.diff?.files ?? const <DiffFile>[];
    final adds = files.fold<int>(0, (n, f) => n + f.additions);
    final dels = files.fold<int>(0, (n, f) => n + f.deletions);
    final folded = pr.collapsedDirs.isNotEmpty;
    return SectionTitle(
      title: 'FILES CHANGED',
      active: pr.pane == PrPane.files,
      count: '${files.length}',
      extra: files.isEmpty ? null : '+$adds −$dels',
      collapsed: pr.filesCollapsed,
      onTap: pr.toggleFiles,
      actions: [
        FoldAllButton(folded: folded, onTap: pr.toggleAllDirs),
        DominantButton(what: 'files', on: pr.lists.dominant == 0, onTap: pr.makeFilesDominant),
      ],
    );
  }
}

class _CommitsHeader extends StatelessWidget {
  const _CommitsHeader({required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) => SectionTitle(
    title: 'COMMITS',
    active: pr.pane == PrPane.commits,
    count: '${pr.commits.length}',
    loading: pr.loading,
    collapsed: pr.commitsCollapsed,
    onTap: pr.toggleCommits,
    actions: [DominantButton(what: 'commits', on: pr.lists.dominant == 1, onTap: pr.makeCommitsDominant)],
  );
}

class _Files extends StatelessWidget {
  const _Files({required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (pr.conflictFiles.isNotEmpty) _ConflictGroup(files: pr.conflictFiles),
      Expanded(child: _tree()),
    ],
  );

  /// The files that would merge cleanly: the conflicted ones are in their own group.
  Widget _tree() => FileTree(
    files: [
      for (final f in pr.diff?.files ?? const <DiffFile>[])
        if (!pr.conflictFiles.contains(f.path))
          TreeFile(path: f.path, status: f.status, additions: f.additions, deletions: f.deletions),
    ],
    selected: pr.selected,
    onSelect: (path) {
      pr.clickPane(PrPane.files);
      pr.select(path);
    },
    collapsed: pr.collapsedDirs,
    onToggleDir: pr.toggleDir,
    onStep: pr.stepFile,
    wheelStep: pr.session.wheelStep,
    selectBottom: pr.selectBottomOfFiles,
  );
}

/// The files that would conflict when merged. Not selectable: the merge opens them in the conflict view.
class _ConflictGroup extends StatelessWidget {
  const _ConflictGroup({required this.files});

  final List<String> files;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conflicts (${files.length})', style: const TextStyle(fontSize: 11)),
        for (final f in files)
          Tooltip(
            message: 'Would conflict when merged; Merge opens it in the conflict view',
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 13),
                  const SizedBox(width: 6),
                  Expanded(child: Text(f, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _CommitList extends StatefulWidget {
  const _CommitList({required this.pr});

  final PrState pr;

  @override
  State<_CommitList> createState() => _CommitListState();
}

class _CommitListState extends State<_CommitList> {
  final _scroll = ScrollController();
  final _cursorKey = GlobalKey();
  int _cursor = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pr = widget.pr;
    if (pr.commitCursor != _cursor) {
      _cursor = pr.commitCursor;
      revealIndex(_scroll, _cursorKey, _cursor);
    }
    return SelectionArea(
      child: WheelMode(onStep: pr.stepCommit, step: pr.session.wheelStep, builder: (context, steps) => _rows(steps)),
    );
  }

  Widget _rows(bool steps) {
    final pr = widget.pr;
    return ListView.builder(
      controller: _scroll,
      physics: steps ? const NeverScrollableScrollPhysics() : null,
      itemCount: pr.commits.length,
      itemBuilder: (context, i) {
        final c = pr.commits[i];
        final cursor = pr.pane == PrPane.commits && i == pr.commitCursor;
        return CommitRow(
          key: i == pr.commitCursor ? _cursorKey : null,
          commit: c,
          selected: cursor || c.sha == pr.narrowed?.sha,
          onTap: () => pr.clickCommit(i),
        );
      },
    );
  }
}

// Molecules ---------------------------------------------------------------------------------------

/// "Showing one commit" above the files, with the way back to the full range.
class _NarrowBanner extends StatelessWidget {
  const _NarrowBanner({required this.commit, required this.onAll});

  final Commit commit;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => Container(
    height: sectionHeader,
    color: C.surface2,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        const Icon(Icons.filter_alt_outlined, size: 14, color: C.accent),
        const SizedBox(width: 6),
        Text(commit.short, style: const TextStyle(fontSize: 11, fontFamily: mono, color: C.accent)),
        const SizedBox(width: 6),
        Expanded(child: Text(commit.subject, style: T.tiny, overflow: TextOverflow.ellipsis)),
        TextButton(onPressed: onAll, child: const Text('All commits', style: TextStyle(fontSize: 11))),
      ],
    ),
  );
}

/// Short sha and subject; the tooltip adds author and age.
class CommitRow extends StatelessWidget {
  const CommitRow({super.key, required this.commit, required this.selected, required this.onTap});

  final Commit commit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${commit.short}  ${commit.author}  ${ago(commit.date)}',
    child: HoverRow(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text(commit.short, style: const TextStyle(fontSize: 11, fontFamily: mono, color: C.faint)),
          const SizedBox(width: 8),
          Expanded(child: Text(commit.subject, style: T.small, overflow: TextOverflow.ellipsis, maxLines: 1)),
        ],
      ),
    ),
  );
}

/// "3h ago", "2d ago".
String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inDays > 0) return '${d.inDays}d ago';
  if (d.inHours > 0) return '${d.inHours}h ago';
  return '${d.inMinutes}m ago';
}

/// A revision picker: lists the branches, filters as you type, takes any revision git accepts.
/// When the filter leaves one branch, it is picked and the focus moves to [next].
///
/// The keyboard stays in the field, which is [RevPicker.focus]; the list has a position of its own.
/// Down opens the list, and with it open Down moves into it, on the first item; Down and Up step
/// through the items, highlighting them and showing each in the field, as an autocomplete drop-down
/// does (the list keeps filtering on what was typed). Up from the first returns to the field with
/// its text back, Enter or Space picks the item, Escape closes the list and puts the text back, and
/// typing edits the item the field shows.
class RevPicker extends StatefulWidget {
  const RevPicker({
    super.key,
    this.label,
    required this.value,
    required this.names,
    required this.focus,
    required this.onPick,
    this.next,
    this.strict = false,
    this.openList,
  });

  /// The width of the label column; the swap button and the merge actions line up with it.
  static const double labelWidth = 38;

  /// The label in front of the field; null: no label column (the branch switcher of Changes).
  final String? label;
  final String? value;
  final List<String> names;
  final PickerFocusNode focus;
  final FocusNode? next;
  final ValueChanged<String> onPick;

  /// Only the listed branches can be picked, and only by Enter or a click: any other revision is
  /// refused, and typing alone never picks (a pick there switches branches).
  final bool strict;

  /// Notifies when the list of branches should open with the keyboard in the field (a shortcut).
  final Listenable? openList;

  @override
  State<RevPicker> createState() => _RevPickerState();
}

class _RevPickerState extends State<RevPicker> {
  final _text = TextEditingController();
  Timer? _auto;

  /// Whether the list is open: typing opens it, Down or a click opens and closes it, Escape closes.
  bool _open = false;

  /// Whether the keyboard is in the list (its item at [_hi] is the one the keys act on).
  bool _inList = false;

  /// The item the keyboard is on in the list; Enter in the field picks it too.
  int _hi = 0;

  /// What the field held when the keyboard went into the list: the list keeps filtering on it while
  /// the field shows the item the keyboard is on, and Up past the first item or Escape puts it back.
  TextEditingValue _query = TextEditingValue.empty;

  /// The drop-down's scroll, and the key of its highlighted row, to keep that row in view.
  final _listScroll = ScrollController();
  final _hiKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _text.text = widget.value ?? '';
    _attach(widget.focus);
    widget.openList?.addListener(_onOpenList);
  }

  @override
  void didUpdateWidget(RevPicker old) {
    super.didUpdateWidget(old);
    if (old.focus != widget.focus) {
      _detach(old.focus);
      _attach(widget.focus);
    }
    if (old.openList != widget.openList) {
      old.openList?.removeListener(_onOpenList);
      widget.openList?.addListener(_onOpenList);
    }
    if (!widget.focus.hasFocus && _text.text != (widget.value ?? '')) _text.text = widget.value ?? '';
  }

  @override
  void dispose() {
    _auto?.cancel();
    _detach(widget.focus);
    widget.openList?.removeListener(_onOpenList);
    _text.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _attach(PickerFocusNode f) {
    f.listHasFocus = () => _inList;
    f.onKeyEvent = _onKey;
    f.addListener(_onFocus);
  }

  void _detach(PickerFocusNode f) {
    f.removeListener(_onFocus);
    if (f.onKeyEvent == _onKey) f.onKeyEvent = null;
    f.listHasFocus = null;
  }

  /// The field's focus changed. On the field it selects the text, as a text field does when it gets
  /// the keyboard. Out of the picker the list closes and the text goes back to the value.
  void _onFocus() {
    if (widget.focus.hasPrimaryFocus) {
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      _repokeText(); // the list shows what _open says now, not what it showed before
      return;
    }
    if (widget.focus.hasFocus) return;
    _auto?.cancel();
    _open = false;
    _inList = false;
    _text.text = widget.value ?? '';
    _repokeText();
  }

  /// Whether the text is what the picker shows when it just got the keyboard (the current value).
  bool _untouched(String q) => q == (widget.value ?? '');

  List<String> _filter(String q) {
    if (_untouched(q) || q.trim().isEmpty) return widget.names;
    final l = q.trim().toLowerCase();
    return widget.names.where((n) => n.toLowerCase().contains(l)).toList();
  }

  /// The items the list shows for [text]: none while the list is closed. While the keyboard is in
  /// the list the field shows an item, and the list stays on what was typed.
  List<String> _optionsFor(String text) => _open ? _filter(_inList ? _query.text : text) : const <String>[];

  void _pick(String v) {
    _auto?.cancel();
    final rev = v.trim();
    if (rev.isEmpty || (widget.strict && !widget.names.contains(rev))) return;
    _open = false;
    _inList = false;
    _text.text = rev;
    if (rev != widget.value) widget.onPick(rev);
    final next = widget.next;
    if (next != null) {
      next.requestFocus();
    } else {
      widget.focus.unfocus();
    }
  }

  /// Typing: the list opens on the filter, and when the filter leaves one branch, it is picked after
  /// a short pause, so a fast typist's next keys don't land in the next picker.
  void _changed(String q) {
    final wasOpen = _open;
    _open = true;
    _inList = false;
    _hi = 0;
    // RawAutocomplete read the options before this callback opened the list: read them again.
    if (!wasOpen) _repokeText();
    _auto?.cancel();
    final hits = _filter(q);
    if (widget.strict || hits.length != 1 || q.trim().isEmpty) return;
    _auto = Timer(const Duration(milliseconds: 150), () {
      if (mounted && widget.focus.hasPrimaryFocus && _filter(_text.text).length == 1) _pick(hits.single);
    });
  }

  /// Enter: a revision that matches no branch (sha, tag, HEAD~3) is taken as typed; otherwise
  /// the item the list is on.
  void _submit(String v) {
    final asTyped = widget.strict ? widget.names.contains(v.trim()) : _untouched(v) || _filter(v).isEmpty || widget.names.contains(v.trim());
    if (asTyped) {
      _pick(v);
    } else if (!(widget.strict && _filter(v).isEmpty)) {
      _pickHighlighted(v);
    }
  }

  /// Picks the item the list is on, if the list shows.
  void _pickHighlighted(String text) {
    final options = _optionsFor(text);
    if (options.isEmpty) return;
    _pick(options[_clampHi(_hi, options.length)]);
  }

  /// Escape: the list closes and the text stays. Typing or Down opens it again.
  void _close() {
    _inList = false;
    _open = false;
    _repokeText();
  }

  /// Escape in the field, when the list is not in the keys' way: closes an open list, else leaves
  /// the picker.
  void _escape() {
    if (_open) {
      _close();
    } else {
      widget.focus.unfocus();
    }
  }

  /// The keys of the field, which keeps the keyboard in both states (see the class comment).
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (!_noModifier()) return KeyEventResult.ignored;
    final key = e.logicalKey;
    final names = _optionsFor(_text.text);
    if (!_inList) {
      if (key != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
      if (!_open) {
        _open = true;
        _repokeText();
      }
      if (_optionsFor(_text.text).isNotEmpty) _enterList(); // the top item, opened or not
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveTo(_clampHi(_hi + 1, names.length), names);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_hi == 0) {
        _leaveList();
      } else {
        _moveTo(_hi - 1, names);
      }
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space) {
      if (names.isEmpty) {
        _leaveList();
      } else {
        _pick(names[_clampHi(_hi, names.length)]);
      }
    } else if (key == LogicalKeyboardKey.escape) {
      _leaveList();
      _close();
    } else {
      final c = e.character;
      final edits = key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete;
      if (!edits && (c == null || c.length != 1 || c.trim().isEmpty)) return KeyEventResult.ignored;
      // Typing goes on from the item the field shows, as in an autocomplete drop-down.
      _keepItem();
      return KeyEventResult.ignored; // the field takes the key
    }
    return KeyEventResult.handled;
  }

  /// Down from the field: the keyboard goes to the list's top item, and the field shows it.
  void _enterList() {
    _query = _text.value;
    _inList = true;
    _moveTo(0, _optionsFor(_query.text));
  }

  /// The keyboard goes to item [i]: it is highlighted, shown in the field and scrolled into view.
  void _moveTo(int i, List<String> names) {
    _hi = i;
    final name = names[i];
    _text.value = TextEditingValue(text: name, selection: TextSelection.collapsed(offset: name.length));
    setState(() {});
    revealIndex(_listScroll, _hiKey, i);
  }

  /// Up past the first item: back in the field, with what it held before the list.
  void _leaveList() {
    if (_inList) _text.value = _query;
    _inList = false;
    setState(() {});
  }

  /// A key that edits while in the list: the field keeps the item it shows and the key edits that.
  void _keepItem() {
    _inList = false;
    setState(() {});
  }

  Widget _itemFor(int i, List<String> names, ValueChanged<String> onSelected) {
    final on = _inList && i == _hi;
    return _BranchOption(key: on ? _hiKey : null, name: names[i], selected: on, onTap: () => onSelected(names[i]));
  }

  void _onOpenList() {
    widget.focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _open = true;
      _repokeText();
    });
  }

  /// A click on the field opens the list of all branches, or closes it when it is open. The list
  /// follows the text, which RawAutocomplete only re-reads when the text changes, so the text is
  /// changed and put back.
  void _toggleList() {
    _inList = false;
    _open = !_open;
    _repokeText();
  }

  void _repokeText() {
    final v = _text.value;
    _text.value = v.copyWith(text: '${v.text} ');
    _text.value = v;
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (widget.label != null) SizedBox(width: RevPicker.labelWidth, child: Text(widget.label!, style: T.tiny)),
      Expanded(
        child: RawAutocomplete<String>(
          textEditingController: _text,
          focusNode: widget.focus,
          optionsBuilder: (v) => _optionsFor(v.text),
          onSelected: _pick,
          fieldViewBuilder: (context, controller, fieldFocus, fieldSubmit) => _RevField(
            controller: controller,
            focus: widget.focus,
            onChanged: _changed,
            onSubmitted: _submit,
            onCancel: _escape,
            onTap: _toggleList,
          ),
          optionsViewBuilder: (context, onSelected, options) {
            final names = options.toList();
            return _RevOptions(
              options: names,
              scroll: _listScroll,
              itemBuilder: (context, i) => _itemFor(i, names, onSelected),
            );
          },
        ),
      ),
    ],
  );
}

class _RevField extends StatelessWidget {
  const _RevField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCancel,
    required this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged, onSubmitted;
  final VoidCallback onCancel, onTap;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onCancel},
    child: ClearOnAltX(
      controller: controller,
      onCleared: onChanged,
      child: TextField(
        controller: controller,
        focusNode: focus,
        style: T.body,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.call_split, size: 13, color: C.muted),
          prefixIconConstraints: const BoxConstraints(minWidth: 28),
          suffixIcon: ClearButton(controller: controller, onCleared: onChanged),
          suffixIconConstraints: ClearButton.constraints,
          hintText: 'branch, tag or sha',
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTap: onTap,
      ),
    ),
  );
}

/// No Ctrl, Alt or Meta: the keys a picker takes are the plain ones.
bool _noModifier() {
  final hw = HardwareKeyboard.instance;
  return !(hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed);
}

/// [i] kept inside a list of [n] items.
int _clampHi(int i, int n) => i < 0 ? 0 : (i >= n ? n - 1 : i);

/// The drop-down under a picker: a box of items, built one by one.
class _RevOptions extends StatelessWidget {
  const _RevOptions({required this.options, required this.scroll, required this.itemBuilder});

  final List<String> options;
  final ScrollController scroll;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Material(
      color: C.surface2,
      elevation: 6,
      borderRadius: BorderRadius.circular(5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280, maxWidth: 240),
        child: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: itemBuilder,
        ),
      ),
    ),
  );
}

// Atoms -------------------------------------------------------------------------------------------

class _BranchOption extends StatelessWidget {
  const _BranchOption({super.key, required this.name, required this.selected, required this.onTap});

  /// The highlight of the item the keyboard is on: the box is [C.surface2], a plain selected row.
  static final _highlight = Color.alphaBlend(C.accent.withValues(alpha: 0.28), C.surface2);

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverRow(
    selected: selected,
    selectedColor: _highlight,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(
      children: [
        const Icon(Icons.call_split, size: 13, color: C.muted),
        const SizedBox(width: 6),
        Expanded(child: Text(name, style: T.body, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
