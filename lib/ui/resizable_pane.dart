import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier, kDebugMode;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:material_ui/material_ui.dart';

import '../backend/models.dart' show Commit;
import 'file_tree.dart';
import 'resize_badge.dart';
import 'text_width.dart';

export 'text_width.dart' show textWidth;
import 'theme.dart';

/// A left pane the mouse can resize by dragging its right edge. Until dragged it is [autoWidth]
/// (the narrowest that still shows all its text); double-clicking the edge goes back to that.
/// [minWidth] is the least a drag can make it: 280 px, as every resizable pane.
class ResizablePane extends StatefulWidget {
  const ResizablePane({super.key, required this.autoWidth, required this.child, required this.minWidth});

  final double autoWidth, minWidth;
  final Widget child;

  @override
  State<ResizablePane> createState() => _ResizablePaneState();
}

class _ResizablePaneState extends State<ResizablePane> {
  double? _dragged;

  /// On while the edge is dragged; only the debug badge listens, not the pane.
  final _resizing = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _resizing.dispose();
    super.dispose();
  }

  double _clamp(double w, double room) => w.clamp(widget.minWidth, math.max(widget.minWidth, room * 0.7));

  void _drag(double width, double room) => setState(() => _dragged = _clamp(width, room));

  void _reset() => setState(() => _dragged = null);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final room = box.maxWidth.isFinite ? box.maxWidth : 1600.0;
      final width = _clamp(_dragged ?? widget.autoWidth, room);
      return Row(
        children: [
          SizedBox(width: width, child: _badged(width, box.hasBoundedHeight ? box.maxHeight : 0)),
          _Edge(
            width: width,
            onWidth: (w) => _drag(w, room),
            onResize: (on) => _resizing.value = on,
            onReset: _reset,
          ),
        ],
      );
    },
  );

  /// The pane, with the debug size badge over it. A release build returns the content itself.
  Widget _badged(double width, double height) {
    if (!kDebugMode) return widget.child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(child: ResizeBadge(width: width, height: height, dragging: _resizing)),
      ],
    );
  }
}

/// The draggable divider: a thin line with a wider hit area.
///
/// The edge stays under the pointer: a drag remembers the shown width and the pointer's x where it
/// began, and every update sets the width from how far the pointer is from there. Adding each
/// delta to the current width lost the part of a move beyond a clamp, so after the pane hit its
/// minimum or maximum the edge no longer came back under the pointer.
class _Edge extends StatefulWidget {
  const _Edge({required this.width, required this.onWidth, required this.onResize, required this.onReset});

  /// The pane's width as shown now.
  final double width;

  /// The width the pointer asks for, unclamped; the pane clamps what it shows.
  final ValueChanged<double> onWidth;

  /// The debug badge: true while the edge is held.
  final ValueChanged<bool> onResize;
  final VoidCallback onReset;

  @override
  State<_Edge> createState() => _EdgeState();
}

class _EdgeState extends State<_Edge> {
  double _startX = 0, _startWidth = 0;

  void _start(DragStartDetails d) {
    _startX = d.globalPosition.dx;
    _startWidth = widget.width;
    widget.onResize(true);
  }

  /// The edge is on the pane's right, so moving right makes the pane wider.
  void _update(DragUpdateDetails d) => widget.onWidth(_startWidth + (d.globalPosition.dx - _startX));

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _start,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: (_) => widget.onResize(false),
      onHorizontalDragCancel: () => widget.onResize(false),
      onDoubleTap: widget.onReset,
      child: const SizedBox(width: 7, child: Center(child: VerticalDivider(width: 1))),
    ),
  );
}

// Natural widths ---------------------------------------------------------------------------------

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
            fileCountsWidth +
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
