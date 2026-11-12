import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Scroll [controller] the least that brings the row at [top] .. [top] + [height] into view.
/// Rows are estimated by the caller (lists build lazily), so a row can end up a little off.
void revealRange(ScrollController controller, double top, double height) {
  if (!controller.hasClients) return;
  final p = controller.position;
  final bottom = top + height;
  if (top < p.pixels) {
    controller.jumpTo(math.max(p.minScrollExtent, top));
  } else if (bottom > p.pixels + p.viewportDimension) {
    controller.jumpTo(math.min(p.maxScrollExtent, bottom - p.viewportDimension));
  }
}

/// Scroll [controller] the least that brings the widget of [context] fully into view, by where it
/// really is (the heights of lazily built rows are only estimates).
void revealContext(ScrollController controller, BuildContext context) {
  if (!controller.hasClients) return;
  final box = context.findRenderObject();
  if (box == null) return;
  final viewport = RenderAbstractViewport.maybeOf(box);
  if (viewport == null) return;
  final atTop = viewport.getOffsetToReveal(box, 0).offset; // the row at the top edge
  final atBottom = viewport.getOffsetToReveal(box, 1).offset; // the row at the bottom edge
  final p = controller.position;
  if (p.pixels > atTop) {
    controller.jumpTo(atTop.clamp(p.minScrollExtent, p.maxScrollExtent));
  } else if (p.pixels < atBottom) {
    controller.jumpTo(atBottom.clamp(p.minScrollExtent, p.maxScrollExtent));
  }
}

/// The render object of the lazily built list [controller] scrolls: it knows which rows are built
/// and where they really are.
RenderSliverMultiBoxAdaptor? _sliverList(ScrollController controller) {
  if (!controller.hasClients) return null;
  RenderSliverMultiBoxAdaptor? found;
  void visit(RenderObject o) {
    if (found != null) return;
    if (o is RenderSliverMultiBoxAdaptor) {
      found = o;
      return;
    }
    o.visitChildren(visit);
  }

  final root = controller.position.context.storageContext.findRenderObject();
  if (root != null) visit(root);
  return found;
}

/// Brings row [index] of a lazily built list into view, without knowing any row height in advance.
/// [key] is on that row's widget. A built row is placed by where it really is. For one not built
/// yet (far off screen) the average height of the rows that are built says where to scroll; it
/// repeats, frame by frame, until the row exists, so a change of font size or row layout needs no
/// change here.
void revealIndex(ScrollController controller, GlobalKey key, int index) {
  var tries = 0;
  void step() {
    if (!controller.hasClients) return;
    final built = key.currentContext;
    if (built != null) return revealContext(controller, built);
    if (++tries > 60) return;
    final list = _sliverList(controller);
    final first = list?.firstChild, last = list?.lastChild;
    if (list != null && first != null && last != null) {
      final from = list.indexOf(first), to = list.indexOf(last);
      if (index < from || index > to) {
        final top = list.childScrollOffset(first) ?? 0;
        final end = (list.childScrollOffset(last) ?? 0) + last.size.height;
        final average = (end - top) / (to - from + 1);
        final p = controller.position;
        final target = list.constraints.precedingScrollExtent + top + average * (index - from);
        controller.jumpTo(target.clamp(p.minScrollExtent, p.maxScrollExtent));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => step());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => step());
  WidgetsBinding.instance.ensureVisualUpdate();
}

/// The index of the last row that is completely inside the visible part of the list, or null when
/// the list is not built yet.
int? lastFullyVisibleIndex(ScrollController controller) {
  final list = _sliverList(controller);
  if (list == null) return null;
  final p = controller.position;
  final bottom = p.pixels + p.viewportDimension;
  int? best;
  for (var child = list.firstChild; child != null; child = list.childAfter(child)) {
    final top = list.constraints.precedingScrollExtent + (list.childScrollOffset(child) ?? 0);
    if (top >= p.pixels - 0.5 && top + child.size.height <= bottom + 0.5) best = list.indexOf(child);
  }
  return best;
}
