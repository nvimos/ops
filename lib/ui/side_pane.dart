import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:material_ui/material_ui.dart';

/// What a mode's right-hand pane shows.
enum SideView {
  /// The `.gitignore` files and their lines.
  ignore,

  /// The highlighted files' content.
  preview,
}

/// The width a side pane has until it is dragged, and the least it can be.
const double sidePaneDefaultWidth = 360;
const double sidePaneMinWidth = 240;

/// The pane may take at most this share of the window, so the list keeps its room.
const double sidePaneMaxShare = 0.6;

/// A right-hand pane with a draggable left edge, as in Purrage: [width] is the width the caller keeps;
/// [onWidth] gets the width while it is dragged and [onDone] the end of a drag (to save it);
/// [onReset] is a double click on the edge, which goes back to [sidePaneDefaultWidth].
///
/// Only this widget listens to [width]: a drag lays the pane and its neighbours out again but
/// rebuilds nothing, because [child] is the same instance on every frame of the drag.
class SidePane extends StatelessWidget {
  const SidePane({
    super.key,
    required this.width,
    required this.onWidth,
    required this.onDone,
    required this.onReset,
    required this.child,
  });

  final ValueListenable<double> width;
  final ValueChanged<double> onWidth;
  final VoidCallback onDone, onReset;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: width,
    child: RepaintBoundary(child: child),
    builder: (context, width, pane) => LayoutBuilder(
      builder: (context, box) {
        final room = box.maxWidth.isFinite ? box.maxWidth : 1600.0;
        final shown = width.clamp(sidePaneMinWidth, math.max(sidePaneMinWidth, room * sidePaneMaxShare)).toDouble();
        return Row(
          children: [
            _LeftEdge(width: shown, onWidth: onWidth, onDone: onDone, onReset: onReset),
            SizedBox(width: shown, child: pane),
          ],
        );
      },
    ),
  );
}

/// The draggable divider: a thin line with a wider hit area, and the resize cursor.
///
/// The edge stays under the pointer: a drag remembers the width and the pointer's x where it began,
/// and every update sets the width from how far the pointer is from there. Summing deltas onto the
/// last built width lost all but one delta per frame (several pointer events arrive between
/// builds), so the edge trailed the mouse like a lever.
class _LeftEdge extends StatefulWidget {
  const _LeftEdge({required this.width, required this.onWidth, required this.onDone, required this.onReset});

  /// The pane's width as shown now.
  final double width;
  final ValueChanged<double> onWidth;
  final VoidCallback onDone, onReset;

  @override
  State<_LeftEdge> createState() => _LeftEdgeState();
}

class _LeftEdgeState extends State<_LeftEdge> {
  double _startX = 0, _startWidth = 0;

  void _start(DragStartDetails d) {
    _startX = d.globalPosition.dx;
    _startWidth = widget.width;
  }

  /// The edge is on the pane's left, so moving right makes the pane narrower.
  void _update(DragUpdateDetails d) => widget.onWidth(_startWidth - (d.globalPosition.dx - _startX));

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _start,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: (_) => widget.onDone(),
      onDoubleTap: widget.onReset,
      child: const SizedBox(width: 7, child: Center(child: VerticalDivider(width: 1))),
    ),
  );
}
