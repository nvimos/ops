import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../backend/models.dart' show Commit;
import 'file_tree.dart';
import 'theme.dart';

/// A left pane the mouse can resize by dragging its right edge. Until dragged it is [autoWidth]
/// (the narrowest that still shows all its text); double-clicking the edge goes back to that.
/// [minWidth] is half the pane's old fixed width: 150 in Pull request, 160 in Changes.
class ResizablePane extends StatefulWidget {
  const ResizablePane({super.key, required this.autoWidth, required this.child, required this.minWidth});

  final double autoWidth, minWidth;
  final Widget child;

  @override
  State<ResizablePane> createState() => _ResizablePaneState();
}

class _ResizablePaneState extends State<ResizablePane> {
  double? _dragged;

  double _clamp(double w, double room) => w.clamp(widget.minWidth, math.max(widget.minWidth, room * 0.7));

  void _drag(double dx, double room) =>
      setState(() => _dragged = _clamp((_dragged ?? widget.autoWidth) + dx, room));

  void _reset() => setState(() => _dragged = null);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final room = box.maxWidth.isFinite ? box.maxWidth : 1600.0;
      return Row(
        children: [
          SizedBox(width: _clamp(_dragged ?? widget.autoWidth, room), child: widget.child),
          _Edge(onDrag: (dx) => _drag(dx, room), onReset: _reset),
        ],
      );
    },
  );
}

/// The draggable divider: a thin line with a wider hit area.
class _Edge extends StatelessWidget {
  const _Edge({required this.onDrag, required this.onReset});

  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      onDoubleTap: onReset,
      child: const SizedBox(width: 7, child: Center(child: VerticalDivider(width: 1))),
    ),
  );
}

// Natural widths ---------------------------------------------------------------------------------

/// The width of one line of [text].
double textWidth(String text, TextStyle style) {
  final p = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)
    ..layout();
  return p.width;
}

const _slack = 16.0;

/// The pane width that fits [content] (the widest row), kept between [least] and [most]: half and
/// 120% of the pane's old fixed width. Dragging can go beyond [most].
double paneWidth(Iterable<double> content, {required double least, required double most}) =>
    (content.fold<double>(0, math.max) + _slack).clamp(least, most);

/// The widest row of a [FileTree] of [files]; [trailing] is the width of each row's end widget.
Iterable<double> fileTreeWidths(List<TreeFile> files, Set<String> collapsed, {double trailing = 0}) => [
  for (final e in treeRows(files, collapsed))
    switch (e) {
      FolderEntry(:final dir, :final count, :final folded) =>
        12 + 14 + 14 + 6 + 12 + textWidth(dir, T.tiny) + (folded ? textWidth('$count', T.tiny) : 0),
      FileEntry(:final file, :final nested) =>
        (nested ? 30 : 12) +
            10 +
            14 +
            8 +
            textWidth(file.path.substring(file.path.lastIndexOf('/') + 1), T.body) +
            (file.additions > 0 ? textWidth('+${file.additions}', const TextStyle(fontSize: 11)) : 0) +
            (file.deletions > 0 ? textWidth(' −${file.deletions}', const TextStyle(fontSize: 11)) : 0) +
            (trailing > 0 ? 6 + trailing : 0),
    },
];

/// The widest commit row: short sha, gap and subject.
Iterable<double> commitWidths(List<Commit> commits) => [
  for (final c in commits)
    24 + textWidth(c.short, const TextStyle(fontSize: 11, fontFamily: mono)) + 8 + textWidth(c.subject, T.small),
];

/// A [SectionTitle] header: chevron, title, count, [extra] text and [actions] icon buttons.
double headerWidth(String title, String count, {String? extra, int actions = 0, double textActions = 0}) =>
    12 + 14 + textWidth(title, T.section) + 6 + textWidth(count, T.tiny) +
    (extra == null ? 0 : 6 + textWidth(extra, T.tiny)) + actions * 28 + textActions + 6;
