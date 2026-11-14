import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../backend/models.dart';
import '../state/pr.dart';
import '../state/session.dart';
import '../tasks/model.dart';
import '../tasks/workspace.dart';
import 'confirm_dialog.dart';
import 'diff_view.dart';
import 'error_view.dart';
import 'file_tree.dart';
import 'list_pair_view.dart';
import 'resizable_pane.dart';
import 'reveal.dart';
import 'tasks/review_panel.dart';
import 'theme.dart';
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
      Expanded(child: _PrMain(pr: _pr, onLine: _jump)),
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
  const _PrMain({required this.pr, required this.onLine});

  final PrState pr;
  final OnDiffLine onLine;

  @override
  Widget build(BuildContext context) {
    final f = pr.selectedFile;
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
      hunk: pr.hunk,
      scroll: pr.diffScroll,
      onLine: onLine,
      headerActions: [
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
    ],
  );
}

/// Ask, then merge head into base; say what happened.
Future<void> mergeBranches(BuildContext context, PrState pr) async {
  final (base, head) = (pr.base!, pr.head!);
  final ok = await confirm(
    context,
    title: 'Merge $head into $base?',
    text:
        'A merge commit on $base; $base is checked out first if it is not the current branch.\n'
        'Local only: nothing is pushed. A conflict undoes the merge.',
    okLabel: 'Merge',
  );
  if (!ok || !context.mounted) return;
  final err = await pr.merge();
  if (!context.mounted) return;
  if (err != null) return showActionError(context, err);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Merged $head into $base'), duration: const Duration(seconds: 3)));
}

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
          names: pr.branchNames,
          focus: pr.baseFocus,
          next: pr.headFocus,
          onPick: pr.pickBase,
        ),
        ActionsLine(pr: pr),
        RevPicker(label: 'head', value: pr.head, names: pr.branchNames, focus: pr.headFocus, onPick: pr.pickHead),
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
  Widget build(BuildContext context) => FileTree(
    files: [
      for (final f in pr.diff?.files ?? const <DiffFile>[])
        TreeFile(path: f.path, status: f.status, additions: f.additions, deletions: f.deletions),
    ],
    selected: pr.selected,
    onSelect: (path) {
      pr.clickPane(PrPane.files);
      pr.select(path);
    },
    collapsed: pr.collapsedDirs,
    onToggleDir: pr.toggleDir,
    selectBottom: pr.selectBottomOfFiles,
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
      child: ListView.builder(
        controller: _scroll,
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
      ),
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
  final FocusNode focus;
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

  /// A click on the field opened the list of all branches (a click again closes it).
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _text.text = widget.value ?? '';
    widget.focus.addListener(_onFocus);
    widget.openList?.addListener(_onOpenList);
  }

  @override
  void didUpdateWidget(RevPicker old) {
    super.didUpdateWidget(old);
    if (old.focus != widget.focus) {
      old.focus.removeListener(_onFocus);
      widget.focus.addListener(_onFocus);
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
    widget.focus.removeListener(_onFocus);
    widget.openList?.removeListener(_onOpenList);
    _text.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (widget.focus.hasFocus) {
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    } else {
      _auto?.cancel();
      _open = false;
      _text.text = widget.value ?? '';
    }
  }

  /// Whether the text is what the picker shows when it just got the keyboard (the current value).
  bool _untouched(String q) => q == (widget.value ?? '');

  List<String> _filter(String q) {
    if (_untouched(q) || q.trim().isEmpty) return widget.names;
    final l = q.trim().toLowerCase();
    return widget.names.where((n) => n.toLowerCase().contains(l)).toList();
  }

  void _pick(String v) {
    _auto?.cancel();
    final rev = v.trim();
    if (rev.isEmpty || (widget.strict && !widget.names.contains(rev))) return;
    _open = false;
    _text.text = rev;
    if (rev != widget.value) widget.onPick(rev);
    final next = widget.next;
    next != null ? next.requestFocus() : widget.focus.unfocus();
  }

  /// Typing: when the filter leaves one branch, pick it after a short pause, so a fast typist's
  /// next keys don't land in the next picker.
  void _changed(String q) {
    _open = false;
    _auto?.cancel();
    final hits = _filter(q);
    if (widget.strict || hits.length != 1 || q.trim().isEmpty) return;
    _auto = Timer(const Duration(milliseconds: 150), () {
      if (mounted && widget.focus.hasFocus && _filter(_text.text).length == 1) _pick(hits.single);
    });
  }

  /// Enter: a revision that matches no branch (sha, tag, HEAD~3) is taken as typed; otherwise
  /// the highlighted branch.
  void _submit(String v, VoidCallback pickHighlighted) {
    final asTyped = widget.strict ? widget.names.contains(v.trim()) : _untouched(v) || _filter(v).isEmpty || widget.names.contains(v.trim());
    if (asTyped) {
      _pick(v);
    } else if (widget.strict && _filter(v).isEmpty) {
      return;
    } else {
      pickHighlighted();
    }
  }

  void _cancel() => widget.focus.unfocus();

  /// A click on the field opens the list of all branches, or closes it when it is open. The list
  /// follows the text, which RawAutocomplete only re-reads when the text changes, so the text is
  /// changed and put back.
  void _toggleList() {
    _open = !_open;
    _repokeText();
  }

  /// The shortcut: focus the field (which selects its text), then show the list once the focus
  /// has settled, so the focus change does not close it again.
  void _onOpenList() {
    widget.focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _open = true;
      _repokeText();
    });
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
          // The drop-down opens when the user starts typing, not when the keys land here.
          optionsBuilder: (v) => _untouched(v.text) ? (_open ? widget.names : const <String>[]) : _filter(v.text),
          onSelected: _pick,
          fieldViewBuilder: (context, controller, focus, submit) => _RevField(
            controller: controller,
            focus: focus,
            onChanged: _changed,
            onSubmitted: (v) => _submit(v, submit),
            onCancel: _cancel,
            onTap: _toggleList,
          ),
          optionsViewBuilder: (context, onSelected, options) => _RevOptions(
            options: options.toList(),
            highlighted: AutocompleteHighlightedOption.of(context),
            onSelected: onSelected,
          ),
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

/// The branches under a picker; the highlighted one is what Enter picks.
class _RevOptions extends StatelessWidget {
  const _RevOptions({required this.options, required this.highlighted, required this.onSelected});

  final List<String> options;
  final int highlighted;
  final ValueChanged<String> onSelected;

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
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (context, i) => _BranchOption(
            name: options[i],
            selected: i == highlighted,
            onTap: () => onSelected(options[i]),
          ),
        ),
      ),
    ),
  );
}

// Atoms -------------------------------------------------------------------------------------------

class _BranchOption extends StatelessWidget {
  const _BranchOption({required this.name, required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverRow(
    selected: selected,
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
