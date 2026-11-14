import 'package:material_ui/material_ui.dart';

import 'reveal.dart';
import 'theme.dart';
import 'wheel_mode.dart';
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
/// The list scrolls to keep the [selected] file in view when it changes (arrow keys).
class FileTree extends StatefulWidget {
  const FileTree({
    super.key,
    required this.files,
    required this.selected,
    required this.onSelect,
    this.collapsed = const {},
    this.onToggleDir,
    this.folderTrailing,
    this.selectBottom,
    this.onStep,
  });

  final List<TreeFile> files;

  /// The wheel steps through the files (-1 / 1) after a middle click, or with Shift (see [WheelMode]);
  /// null: the wheel only scrolls.
  final ValueChanged<int>? onStep;

  /// A widget at the end of a folder row (lined up with the files' trailing widgets), by folder.
  final Widget? Function(String dir)? folderTrailing;

  /// Notifies when the keyboard enters this list from below: the file lowest in the visible part of
  /// the list is selected (not the heading, not the last file when the list is scrolled).
  final Listenable? selectBottom;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Set<String> collapsed;
  final ValueChanged<String>? onToggleDir;

  @override
  State<FileTree> createState() => _FileTreeState();
}

/// Estimated row heights, for scrolling the selected file into view.
const _treePad = 4.0;

class _FileTreeState extends State<FileTree> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.selectBottom?.addListener(_onBottomRequest);
  }

  void _onBottomRequest() => WidgetsBinding.instance.addPostFrameCallback((_) => _selectBottom());

  /// Selects the last file whose row is completely inside the visible part of the list (the file
  /// nearest the bottom edge; a folder row there is passed over).
  void _selectBottom() {
    if (!mounted) return;
    final rows = treeRows(widget.files, widget.collapsed);
    var i = lastFullyVisibleIndex(_scroll) ?? rows.length - 1;
    while (i >= 0 && rows[i] is! FileEntry) {
      i--;
    }
    final pick = i >= 0 ? (rows[i] as FileEntry).file.path : rows.whereType<FileEntry>().firstOrNull?.file.path;
    if (pick != null) widget.onSelect(pick);
  }

  @override
  void didUpdateWidget(FileTree old) {
    super.didUpdateWidget(old);
    if (widget.selectBottom != old.selectBottom) {
      old.selectBottom?.removeListener(_onBottomRequest);
      widget.selectBottom?.addListener(_onBottomRequest);
    }
    if (widget.selected != old.selected) _reveal();
  }

  @override
  void dispose() {
    widget.selectBottom?.removeListener(_onBottomRequest);
    _scroll.dispose();
    super.dispose();
  }

  /// The row of the selected file, so its real position can be found.
  final _selectedKey = GlobalKey();

  /// Scrolls the selected file into view (see [revealIndex]); no row height is assumed.
  void _reveal() {
    final rows = treeRows(widget.files, widget.collapsed);
    final i = rows.indexWhere((e) => e is FileEntry && e.file.path == widget.selected);
    if (i >= 0) revealIndex(_scroll, _selectedKey, i);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.onStep;
    if (step == null) return _list(scrolls: true);
    return WheelMode(onStep: step, builder: (context, steps) => _list(scrolls: !steps));
  }

  Widget _list({required bool scrolls}) {
    final rows = treeRows(widget.files, widget.collapsed);
    return ListView.builder(
      controller: _scroll,
      physics: scrolls ? null : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: _treePad),
      itemCount: rows.length,
      itemBuilder: (context, i) => switch (rows[i]) {
        FolderEntry(:final dir, :final count, :final folded) => FolderRow(
          dir: dir,
          count: count,
          folded: folded,
          onTap: widget.onToggleDir == null ? null : () => widget.onToggleDir!(dir),
          trailing: widget.folderTrailing?.call(dir),
        ),
        FileEntry(:final file, :final nested) => FileRow(
          key: file.path == widget.selected ? _selectedKey : null,
          file: file,
          nested: nested,
          selected: file.path == widget.selected,
          onTap: () => widget.onSelect(file.path),
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
  const FolderRow({super.key, required this.dir, required this.count, required this.folded, this.onTap, this.trailing});

  final String dir;
  final int count;
  final bool folded;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (onTap != null) Icon(folded ? Icons.chevron_right : Icons.expand_more, size: 14, color: C.faint),
        Icon(folded ? Icons.folder_outlined : Icons.folder_open_outlined, size: 14, color: C.faint),
        const SizedBox(width: 6),
        Expanded(child: Text(dir, style: T.tiny, overflow: TextOverflow.ellipsis)),
        if (folded) Text('$count', style: T.tiny),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
    // The right padding is the file rows' (10), so the trailing widgets line up.
    if (onTap == null) return Padding(padding: const EdgeInsets.fromLTRB(12, 8, 10, 2), child: row);
    return HoverRow(onTap: onTap, padding: const EdgeInsets.fromLTRB(12, 6, 10, 3), child: row);
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
      pointer: false, // that a file can be clicked is obvious: the plain cursor
      padding: EdgeInsets.fromLTRB(nested ? 30 : 12, 5, 10, 5),
      child: Row(
        children: [
          StatusMark(f.status),
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

/// The mark of a file's status: the symbols and colors oil-git.nvim draws in Oil by default
/// (`+` added, `~` modified, `->` renamed, `D` deleted, `!` conflict, `?` untracked).
class StatusMark extends StatelessWidget {
  const StatusMark(this.status, {super.key, this.size = 14});

  final String status;
  final double size;

  static (String, Color) _look(String status) => switch (status) {
    'added' => ('+', const Color(0xFFA6E3A1)),
    'renamed' => ('->', const Color(0xFFCBA6F7)),
    'deleted' => ('D', const Color(0xFFF38BA8)),
    'conflicted' => ('!', const Color(0xFFFAB387)),
    'untracked' => ('?', const Color(0xFF89B4FA)),
    _ => ('~', const Color(0xFFF9E2AF)), // modified
  };

  @override
  Widget build(BuildContext context) {
    final (sign, color) = _look(status);
    return SizedBox(
      width: size + 4, // the two-character `->` fits; the other marks centre in the same width
      child: Center(
        child: Text(
          sign,
          style: TextStyle(fontFamily: mono, fontSize: size - 1, height: 1, fontWeight: FontWeight.w600, color: color),
        ),
      ),
    );
  }
}
