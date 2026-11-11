import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// One file in a changed-files tree.
class TreeFile {
  TreeFile({required this.path, required this.status, this.additions = 0, this.deletions = 0, this.trailing});
  final String path;
  final String status; // added | deleted | modified | renamed | untracked | conflicted
  final int additions, deletions;
  final Widget? trailing;
}

IconData statusIcon(String status) => switch (status) {
  'added' || 'untracked' => Icons.add_box_outlined,
  'deleted' => Icons.indeterminate_check_box_outlined,
  'renamed' => Icons.drive_file_rename_outline,
  'conflicted' => Icons.warning_amber_rounded,
  _ => Icons.edit_square,
};

Color statusColor(String status) => switch (status) {
  'added' || 'untracked' => C.green,
  'deleted' => C.red,
  'renamed' => C.purple,
  'conflicted' => C.yellow,
  _ => C.yellow,
};

/// Changed files grouped by folder, folders sorted, files sorted inside them.
/// With [onToggleDir], a click on a folder collapses or expands it; [collapsed] holds the folded ones.
class FileTree extends StatelessWidget {
  const FileTree({
    super.key,
    required this.files,
    required this.selected,
    required this.onSelect,
    this.collapsed = const {},
    this.onToggleDir,
  });

  final List<TreeFile> files;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Set<String> collapsed;
  final ValueChanged<String>? onToggleDir;

  @override
  Widget build(BuildContext context) {
    final byDir = <String, List<TreeFile>>{};
    for (final f in files) {
      final i = f.path.lastIndexOf('/');
      byDir.putIfAbsent(i < 0 ? '' : f.path.substring(0, i), () => []).add(f);
    }
    final dirs = byDir.keys.toList()..sort();
    final rows = <Widget>[];
    for (final d in dirs) {
      final list = byDir[d]!..sort((a, b) => a.path.compareTo(b.path));
      final folded = collapsed.contains(d);
      if (d.isNotEmpty) {
        final row = Row(
          children: [
            if (onToggleDir != null) ...[
              Icon(folded ? Icons.chevron_right : Icons.expand_more, size: 14, color: C.faint),
              const SizedBox(width: 2),
            ],
            Icon(folded ? Icons.folder_outlined : Icons.folder_open_outlined, size: 14, color: C.faint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(d, style: T.tiny, overflow: TextOverflow.ellipsis),
            ),
            if (folded) Text('${list.length}', style: T.tiny),
          ],
        );
        rows.add(
          onToggleDir == null
              ? Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 2), child: row)
              : HoverRow(
                  onTap: () => onToggleDir!(d),
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 3),
                  child: row,
                ),
        );
      }
      if (folded) continue;
      for (final f in list) {
        final name = f.path.substring(f.path.lastIndexOf('/') + 1);
        rows.add(
          HoverRow(
            selected: f.path == selected,
            onTap: () => onSelect(f.path),
            padding: EdgeInsets.fromLTRB(d.isEmpty ? 12 : 30, 5, 10, 5),
            child: Row(
              children: [
                Icon(statusIcon(f.status), size: 14, color: statusColor(f.status)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name, style: T.body, overflow: TextOverflow.ellipsis),
                ),
                if (f.additions > 0) Text('+${f.additions}', style: const TextStyle(fontSize: 11, color: C.green)),
                if (f.deletions > 0) ...[
                  const SizedBox(width: 4),
                  Text('−${f.deletions}', style: const TextStyle(fontSize: 11, color: C.red)),
                ],
                if (f.trailing != null) ...[const SizedBox(width: 6), f.trailing!],
              ],
            ),
          ),
        );
      }
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: rows);
  }
}
