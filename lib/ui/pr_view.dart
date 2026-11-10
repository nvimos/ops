import 'package:flutter/material.dart';

import '../backend/models.dart';
import '../state/pr.dart';
import '../state/session.dart';
import '../tasks/model.dart';
import '../tasks/workspace.dart';
import 'diff_view.dart';
import 'file_tree.dart';
import 'theme.dart';
import 'widgets.dart';

/// Two branches as a pull request: pickers and commits on the left, files and the diff on the
/// right, like GitHub's "Files changed" tab.
class PrView extends StatefulWidget {
  const PrView({super.key, this.state, this.reviewing, this.workspace, this.onStopReview});

  /// Shared state (the Tasks mode opens a review for a branch); created here when null.
  final PrState? state;

  /// The task being reviewed (from the Tasks mode), and the workspace it lives in.
  final Task? reviewing;
  final Workspace? workspace;
  final VoidCallback? onStopReview;

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pr,
      builder: (context, _) {
        final pr = _pr;
        final t = widget.reviewing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t != null)
              Container(
                color: C.surface2,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.task_alt, size: 15, color: C.accent),
                    const SizedBox(width: 8),
                    Text(
                      t.id,
                      style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.muted),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(t.title, style: T.body, overflow: TextOverflow.ellipsis),
                    ),
                    SmallButton('Done reviewing', onPressed: widget.onStopReview),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: 300, child: _Sidebar(pr: pr)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _main(pr)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _main(PrState pr) {
    if (pr.error != null) return Empty(pr.error!);
    if (pr.base == pr.head) return const Empty('Pick two different branches.');
    final f = pr.selectedFile;
    if (pr.diff == null) return Empty(pr.loading ? 'Loading…' : 'No diff.');
    if (pr.diff!.files.isEmpty) return const Empty('No changes between these branches.');
    if (f == null) return const Empty('Pick a file.');
    return DiffView(file: f, onLine: (line, isOld) => _jump(f, line, isOld));
  }

  Future<void> _jump(DiffFile f, int line, bool isOld) async {
    final s = SessionScope.read(context);
    final pr = _pr;
    final rev = isOld ? pr.diff!.mergeBase : pr.head!;
    final path = isOld ? f.oldPath : f.path;
    final err = await s.run((b) => s.repo?.head == rev && !isOld ? b.open(path, line) : b.show(rev, path, line));
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.pr});

  final PrState pr;

  @override
  Widget build(BuildContext context) {
    final names = pr.branches?.list.map((b) => b.name).toList() ?? [];
    final files = pr.diff?.files ?? [];
    final adds = files.fold<int>(0, (n, f) => n + f.additions);
    final dels = files.fold<int>(0, (n, f) => n + f.deletions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BranchPicker(
                label: 'base',
                value: pr.base,
                names: names,
                onPick: (v) => pr.pick(base: v),
              ),
              Center(
                child: IconButton(
                  tooltip: 'Swap',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: pr.swap,
                  icon: const Icon(Icons.swap_vert, color: C.muted),
                ),
              ),
              _BranchPicker(
                label: 'head',
                value: pr.head,
                names: names,
                onPick: (v) => pr.pick(head: v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _SectionTitle('COMMITS', '${pr.commits.length}', loading: pr.loading),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in pr.commits)
                Tooltip(
                  message: '${c.short}  ${c.author}  ${_ago(c.date)}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          c.short,
                          style: const TextStyle(fontSize: 11, fontFamily: mono, color: C.faint),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(c.subject, style: T.small, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        _SectionTitle('FILES CHANGED', '${files.length}', extra: files.isEmpty ? null : '+$adds −$dels'),
        Expanded(
          child: FileTree(
            files: [
              for (final f in files)
                TreeFile(path: f.path, status: f.status, additions: f.additions, deletions: f.deletions),
            ],
            selected: pr.selected,
            onSelect: pr.select,
          ),
        ),
      ],
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inDays > 0) return '${d.inDays}d ago';
  if (d.inHours > 0) return '${d.inHours}h ago';
  return '${d.inMinutes}m ago';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.count, {this.extra, this.loading = false});

  final String title, count;
  final String? extra;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Text(title, style: T.section),
          const SizedBox(width: 6),
          Text(count, style: T.tiny),
          const Spacer(),
          if (extra != null) Text(extra!, style: T.tiny),
          if (loading) const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
        ],
      ),
    );
  }
}

class _BranchPicker extends StatelessWidget {
  const _BranchPicker({required this.label, required this.value, required this.names, required this.onPick});

  final String label;
  final String? value;
  final List<String> names;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 38, child: Text(label, style: T.tiny)),
        Expanded(
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: C.surface2,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: C.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: names.contains(value) ? value : null,
                isExpanded: true,
                isDense: true,
                dropdownColor: C.surface2,
                style: T.body,
                icon: const Icon(Icons.expand_more, size: 16, color: C.muted),
                items: [
                  for (final n in names)
                    DropdownMenuItem(
                      value: n,
                      child: Row(
                        children: [
                          const Icon(Icons.call_split, size: 13, color: C.muted),
                          const SizedBox(width: 6),
                          Expanded(child: Text(n, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onPick(v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
