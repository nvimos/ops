import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/models.dart';
import '../state/pr.dart';
import '../state/session.dart';
import '../tasks/model.dart';
import '../tasks/workspace.dart';
import 'diff_view.dart';
import 'error_view.dart';
import 'file_tree.dart';
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

  /// Show a diff line in Neovim: the working tree file when head is checked out and the view
  /// shows the full range, else a read-only copy at the revision.
  Future<void> _jump(int line, bool isOld) async {
    final s = SessionScope.read(context);
    final pr = _pr;
    final f = pr.selectedFile!;
    final n = pr.narrowed;
    final rev = isOld ? (n == null ? pr.diff!.mergeBase : '${n.sha}~1') : (n?.sha ?? pr.head!);
    final path = isOld ? f.oldPath : f.path;
    final live = !isOld && n == null && s.repo?.head == pr.head;
    _report(await s.run((b) => live ? b.open(path, line) : b.show(rev, path, line)));
  }

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

  Widget _columns(Task? t) => Row(
    children: [
      SizedBox(width: 300, child: _Sidebar(pr: _pr)),
      const VerticalDivider(width: 1),
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
    return DiffView(
      file: f,
      sideBySide: pr.layout == DiffLayout.sideBySide,
      wrap: pr.wrap,
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
      _Pickers(pr: pr),
      const Divider(height: 1),
      Expanded(child: _Lists(pr: pr)),
    ],
  );
}

class _Pickers extends StatelessWidget {
  const _Pickers({required this.pr});

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
        Center(
          child: IconButton(
            tooltip: 'Swap (gs)',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: pr.swap,
            icon: const Icon(Icons.swap_vert, color: C.muted),
          ),
        ),
        RevPicker(label: 'head', value: pr.head, names: pr.branchNames, focus: pr.headFocus, onPick: pr.pickHead),
      ],
    ),
  );
}

/// Row heights the left pane works with.
const _header = 32.0, _fileRow = 26.0, _commitRow = 24.0;

/// Heights of the two lists; null: it takes the rest. The non-dominant list gets at most 6 rows,
/// or 3 when the files would not fit; collapsed commits get none.
({double? files, double? commits}) leftPaneHeights(PrState pr, double height) {
  final files = pr.diff?.files ?? const <DiffFile>[];
  final dirs = {for (final f in files) dirOf(f.path)}..remove('');
  final shownFiles = files.where((f) => !pr.collapsedDirs.contains(dirOf(f.path))).length;
  final filesNeed = (shownFiles + dirs.length) * _fileRow + 8;
  final free = height - 2 * _header - (pr.narrowed != null ? _header : 0);
  final n = pr.commits.length;
  if (pr.commitsCollapsed) return (files: null, commits: 0);
  if (pr.dominant == Dominant.commits) return (files: math.min(filesNeed, 3 * _fileRow + 8), commits: null);
  final rows = free - math.min(n, 6) * _commitRow < filesNeed ? math.min(n, 3) : math.min(n, 6);
  return (files: null, commits: rows * _commitRow);
}

/// FILES CHANGED above COMMITS, sized by [leftPaneHeights].
class _Lists extends StatelessWidget {
  const _Lists({required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final h = leftPaneHeights(pr, c.maxHeight);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pr.narrowed != null) _NarrowBanner(commit: pr.narrowed!, onAll: pr.showAllCommits),
          _FilesHeader(pr: pr),
          _sized(h.files, _Files(pr: pr)),
          const Divider(height: 1),
          _CommitsHeader(pr: pr),
          if (h.commits != 0) _sized(h.commits, _CommitList(pr: pr)),
        ],
      );
    },
  );

  static Widget _sized(double? height, Widget child) =>
      height == null ? Expanded(child: child) : SizedBox(height: height, child: child);
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
      count: '${files.length}',
      extra: files.isEmpty ? null : '+$adds −$dels',
      actions: [
        IconToggle(
          icon: folded ? Icons.unfold_more : Icons.unfold_less,
          tip: folded ? 'Expand all folders (zR)' : 'Collapse all folders (zM)',
          onTap: pr.toggleAllDirs,
        ),
        IconToggle(
          icon: Icons.open_in_full,
          tip: 'Give the files the most room',
          on: pr.dominant == Dominant.files,
          onTap: pr.makeFilesDominant,
        ),
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
    count: '${pr.commits.length}',
    loading: pr.loading,
    collapsed: pr.commitsCollapsed,
    onTap: pr.toggleCommits,
    actions: [
      IconToggle(
        icon: Icons.open_in_full,
        tip: 'Give the commits the most room',
        on: pr.dominant == Dominant.commits,
        onTap: pr.makeCommitsDominant,
      ),
    ],
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
    onSelect: pr.select,
    collapsed: pr.collapsedDirs,
    onToggleDir: pr.toggleDir,
  );
}

class _CommitList extends StatelessWidget {
  const _CommitList({required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: ListView.builder(
      itemCount: pr.commits.length,
      itemBuilder: (context, i) {
        final c = pr.commits[i];
        return CommitRow(commit: c, selected: c.sha == pr.narrowed?.sha, onTap: () => pr.narrow(c));
      },
    ),
  );
}

// Molecules ---------------------------------------------------------------------------------------

/// "Showing one commit" above the files, with the way back to the full range.
class _NarrowBanner extends StatelessWidget {
  const _NarrowBanner({required this.commit, required this.onAll});

  final Commit commit;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => Container(
    height: _header,
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

/// A list header: title, count, extra text, spinner, actions; with [collapsed], a chevron and a
/// click that folds the list.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.count,
    this.extra,
    this.loading = false,
    this.actions = const [],
    this.onTap,
    this.collapsed,
  });

  final String title, count;
  final String? extra;
  final bool loading;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final bool? collapsed;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.fromLTRB(12, 0, 6, 0);
    final row = Row(
      children: [
        if (collapsed != null) Icon(collapsed! ? Icons.chevron_right : Icons.expand_more, size: 14, color: C.muted),
        Text(title, style: T.section),
        const SizedBox(width: 6),
        Text(count, style: T.tiny),
        const Spacer(),
        if (extra != null) Text(extra!, style: T.tiny),
        if (loading) const _Spinner(),
        ...actions,
      ],
    );
    return SizedBox(
      height: _header,
      child: onTap == null ? Padding(padding: pad, child: row) : HoverRow(onTap: onTap, padding: pad, child: row),
    );
  }
}

/// A revision picker: lists the branches, filters as you type, takes any revision git accepts.
/// When the filter leaves one branch, it is picked and the focus moves to [next].
class RevPicker extends StatefulWidget {
  const RevPicker({
    super.key,
    required this.label,
    required this.value,
    required this.names,
    required this.focus,
    required this.onPick,
    this.next,
  });

  final String label;
  final String? value;
  final List<String> names;
  final FocusNode focus;
  final FocusNode? next;
  final ValueChanged<String> onPick;

  @override
  State<RevPicker> createState() => _RevPickerState();
}

class _RevPickerState extends State<RevPicker> {
  final _text = TextEditingController();
  bool _typed = false; // the text differs from the value because the user typed
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _text.text = widget.value ?? '';
    widget.focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(RevPicker old) {
    super.didUpdateWidget(old);
    if (old.focus != widget.focus) {
      old.focus.removeListener(_onFocus);
      widget.focus.addListener(_onFocus);
    }
    if (!widget.focus.hasFocus && _text.text != (widget.value ?? '')) _text.text = widget.value ?? '';
  }

  @override
  void dispose() {
    _auto?.cancel();
    widget.focus.removeListener(_onFocus);
    _text.dispose();
    super.dispose();
  }

  void _onFocus() {
    _typed = false;
    if (widget.focus.hasFocus) {
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    } else {
      _auto?.cancel();
      _text.text = widget.value ?? '';
    }
  }

  List<String> _filter(String q) {
    if (!_typed || q.trim().isEmpty) return widget.names;
    final l = q.trim().toLowerCase();
    return widget.names.where((n) => n.toLowerCase().contains(l)).toList();
  }

  void _pick(String v) {
    _auto?.cancel();
    final rev = v.trim();
    if (rev.isEmpty) return;
    _typed = false;
    _text.text = rev;
    if (rev != widget.value) widget.onPick(rev);
    final next = widget.next;
    next != null ? next.requestFocus() : widget.focus.unfocus();
  }

  /// Typing: when the filter leaves one branch, pick it after a short pause, so a fast typist's
  /// next keys don't land in the next picker.
  void _changed(String q) {
    _typed = true;
    _auto?.cancel();
    final hits = _filter(q);
    if (hits.length != 1 || q.trim().isEmpty) return;
    _auto = Timer(const Duration(milliseconds: 150), () {
      if (mounted && widget.focus.hasFocus && _filter(_text.text).length == 1) _pick(hits.single);
    });
  }

  /// Enter: a revision that matches no branch (sha, tag, HEAD~3) is taken as typed; otherwise
  /// the highlighted branch.
  void _submit(String v, VoidCallback pickHighlighted) {
    if (_filter(v).isEmpty || widget.names.contains(v.trim())) {
      _pick(v);
    } else {
      pickHighlighted();
    }
  }

  void _cancel() => widget.focus.unfocus();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 38, child: Text(widget.label, style: T.tiny)),
      Expanded(
        child: RawAutocomplete<String>(
          textEditingController: _text,
          focusNode: widget.focus,
          optionsBuilder: (v) => _filter(v.text),
          onSelected: _pick,
          fieldViewBuilder: (context, controller, focus, submit) => _RevField(
            controller: controller,
            focus: focus,
            onChanged: _changed,
            onSubmitted: (v) => _submit(v, submit),
            onCancel: _cancel,
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
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged, onSubmitted;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onCancel},
    child: TextField(
      controller: controller,
      focusNode: focus,
      style: T.body,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.call_split, size: 13, color: C.muted),
        prefixIconConstraints: BoxConstraints(minWidth: 28),
        hintText: 'branch, tag or sha',
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
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

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 6),
    child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
  );
}

/// A small icon button that shows whether its option is on.
class IconToggle extends StatelessWidget {
  const IconToggle({super.key, required this.icon, required this.tip, required this.onTap, this.on = false});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool on;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(4),
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: on ? C.accent.withValues(alpha: .15) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 14, color: on ? C.accent : C.muted),
      ),
    ),
  );
}
