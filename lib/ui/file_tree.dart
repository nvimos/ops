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
    final rows = treeRows(files, collapsed);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, i) => switch (rows[i]) {
        FolderEntry(:final dir, :final count, :final folded) => FolderRow(
          dir: dir,
          count: count,
          folded: folded,
          onTap: onToggleDir == null ? null : () => onToggleDir!(dir),
        ),
        FileEntry(:final file, :final nested) => FileRow(
          file: file,
          nested: nested,
          selected: file.path == selected,
          onTap: () => onSelect(file.path),
        ),
      },
    );
  }
}

/// A row of the tree: a folder (not for top-level files) or a file of an unfolded folder.
sealed class TreeEntry {}

class FolderEntry extends TreeEntry {
  FolderEntry(this.dir, this.count, {required this.folded});
  final String dir;
  final int count;
  final bool folded;
}

class FileEntry extends TreeEntry {
  FileEntry(this.file, {required this.nested});
  final TreeFile file;
  final bool nested;
}

/// The rows the tree shows: folders sorted, files sorted inside them, folded folders' files left out.
List<TreeEntry> treeRows(List<TreeFile> files, Set<String> collapsed) {
  final byDir = <String, List<TreeFile>>{};
  for (final f in files) {
    final i = f.path.lastIndexOf('/');
    byDir.putIfAbsent(i < 0 ? '' : f.path.substring(0, i), () => []).add(f);
  }
  return [
    for (final d in byDir.keys.toList()..sort()) ...[
      if (d.isNotEmpty) FolderEntry(d, byDir[d]!.length, folded: collapsed.contains(d)),
      if (!collapsed.contains(d))
        for (final f in byDir[d]!..sort((a, b) => a.path.compareTo(b.path))) FileEntry(f, nested: d.isNotEmpty),
    ],
  ];
}

/// A folder row; clickable (with a chevron) when folders fold.
class FolderRow extends StatelessWidget {
  const FolderRow({super.key, required this.dir, required this.count, required this.folded, this.onTap});

  final String dir;
  final int count;
  final bool folded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (onTap != null) Icon(folded ? Icons.chevron_right : Icons.expand_more, size: 14, color: C.faint),
        Icon(folded ? Icons.folder_outlined : Icons.folder_open_outlined, size: 14, color: C.faint),
        const SizedBox(width: 6),
        Expanded(child: Text(dir, style: T.tiny, overflow: TextOverflow.ellipsis)),
        if (folded) Text('$count', style: T.tiny),
      ],
    );
    if (onTap == null) return Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 2), child: row);
    return HoverRow(onTap: onTap, padding: const EdgeInsets.fromLTRB(12, 6, 12, 3), child: row);
  }
}

/// A file row: status icon, name, +/− counts, and the caller's trailing widget.
class FileRow extends StatelessWidget {
  const FileRow({super.key, required this.file, required this.nested, required this.selected, required this.onTap});

  final TreeFile file;
  final bool nested, selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = file;
    return HoverRow(
      selected: selected,
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(nested ? 30 : 12, 5, 10, 5),
      child: Row(
        children: [
          Icon(statusIcon(f.status), size: 14, color: statusColor(f.status)),
          const SizedBox(width: 8),
          Expanded(child: Text(f.path.substring(f.path.lastIndexOf('/') + 1), style: T.body, overflow: TextOverflow.ellipsis)),
          if (f.additions > 0) Text('+${f.additions}', style: const TextStyle(fontSize: 11, color: C.green)),
          if (f.deletions > 0) Text(' −${f.deletions}', style: const TextStyle(fontSize: 11, color: C.red)),
          if (f.trailing != null) ...[const SizedBox(width: 6), f.trailing!],
        ],
      ),
    );
  }
}
