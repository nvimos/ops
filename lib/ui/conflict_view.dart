import 'package:material_ui/material_ui.dart';

import '../backend/models.dart';
import '../state/merge_conflict.dart';
import '../state/pr.dart';
import 'error_view.dart';
import 'widgets.dart';

/// The merge that stopped with conflicts: its files on the left, the hunks of the open file on the
/// right, each hunk with a button per side. Shown in place of the diff while the merge is open.
class ConflictView extends StatelessWidget {
  const ConflictView({super.key, required this.pr, required this.conflict});

  final PrState pr;
  final MergeConflict conflict;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConflictBar(pr: pr, conflict: conflict),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 260, child: _ConflictFiles(pr: pr, conflict: conflict)),
              const VerticalDivider(width: 1),
              Expanded(child: _ConflictHunks(pr: pr, conflict: conflict)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Run a conflict action; a failure shows as a short snackbar with its details.
Future<void> _run(BuildContext context, Future<String?> Function() action) async {
  final err = await action();
  if (context.mounted) showActionError(context, err);
}

class _ConflictBar extends StatelessWidget {
  const _ConflictBar({required this.pr, required this.conflict});

  final PrState pr;
  final MergeConflict conflict;

  @override
  Widget build(BuildContext context) {
    final left = conflict.unresolved.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Merge ${conflict.head} into ${conflict.base}: '
              '${left == 0 ? 'all files resolved' : '$left file${left == 1 ? '' : 's'} left'}',
            ),
          ),
          Tooltip(
            message: 'Complete the merge on ${conflict.base}',
            child: SmallButton(
              'finish',
              icon: Icons.check,
              primary: true,
              onPressed: left == 0 ? () => _run(context, pr.finishConflict) : null,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Throw the merge away; ${conflict.base} is not touched',
            child: SmallButton('abort', icon: Icons.close, onPressed: () => _run(context, pr.abortConflict)),
          ),
        ],
      ),
    );
  }
}

class _ConflictFiles extends StatelessWidget {
  const _ConflictFiles({required this.pr, required this.conflict});

  final PrState pr;
  final MergeConflict conflict;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: conflict.files.length,
      itemBuilder: (context, i) {
        final file = conflict.files[i];
        final resolved = !conflict.unresolved.contains(file);
        return _FileRow(
          name: file,
          selected: conflict.file == file,
          resolved: resolved,
          onOpen: () => _run(context, () => pr.openConflictFile(file)),
          onAdd: resolved ? null : () => _run(context, () => pr.addConflictFile(file)),
          onNvim: () => _run(context, () => openInNvimQt('${conflict.path}/$file')),
        );
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.selected,
    required this.resolved,
    required this.onOpen,
    required this.onAdd,
    required this.onNvim,
  });

  final String name;
  final bool selected, resolved;
  final VoidCallback onOpen;
  final VoidCallback? onAdd;
  final VoidCallback onNvim;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(resolved ? Icons.check_circle : Icons.warning_amber, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
          ),
          Tooltip(
            message: 'Open in nvim-qt',
            child: SmallButton('nvim', onPressed: onNvim),
          ),
          if (onAdd != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Mark resolved (add); refused while the file has conflict markers',
              child: SmallButton('add', onPressed: onAdd),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConflictHunks extends StatelessWidget {
  const _ConflictHunks({required this.pr, required this.conflict});

  final PrState pr;
  final MergeConflict conflict;

  @override
  Widget build(BuildContext context) {
    final file = conflict.file;
    if (file == null) return const Center(child: Text('Pick a file'));
    if (conflict.hunks.isEmpty) return Center(child: Text('$file has no conflict hunks'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: conflict.hunks.length,
      itemBuilder: (context, i) => _HunkCard(
        index: i,
        hunk: conflict.hunks[i],
        oursLabel: conflict.base,
        theirsLabel: conflict.head,
        onOurs: () => _run(context, () => pr.pickHunk(i, 'ours')),
        onTheirs: () => _run(context, () => pr.pickHunk(i, 'theirs')),
      ),
    );
  }
}

class _HunkCard extends StatelessWidget {
  const _HunkCard({
    required this.index,
    required this.hunk,
    required this.oursLabel,
    required this.theirsLabel,
    required this.onOurs,
    required this.onTheirs,
  });

  final int index;
  final ConflictHunk hunk;
  final String oursLabel, theirsLabel;
  final VoidCallback onOurs, onTheirs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Conflict ${index + 1}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          _Side(label: 'ours: $oursLabel', lines: hunk.ours, button: 'take ours', tip: 'Keep the $oursLabel side', onTap: onOurs),
          const SizedBox(height: 4),
          _Side(label: 'theirs: $theirsLabel', lines: hunk.theirs, button: 'take theirs', tip: 'Keep the $theirsLabel side', onTap: onTheirs),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.lines, required this.button, required this.tip, required this.onTap});

  final String label, button, tip;
  final List<String> lines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            Tooltip(message: tip, child: SmallButton(button, onPressed: onTap)),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            lines.isEmpty ? '(nothing)' : lines.join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
          ),
        ),
      ],
    );
  }
}
