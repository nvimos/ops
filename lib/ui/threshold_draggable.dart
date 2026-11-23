import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// How far a mouse press has to travel before it becomes a drag, in logical pixels.
///
/// Flutter's own mouse slop is 1 px (`kPrecisePointerHitSlop`), so the wobble of a click picked the
/// item up and swallowed the click. Windows uses about 4 px (`SM_CXDRAG`); twice that forgives a
/// click and is not felt when a drag is meant. Touch keeps Flutter's larger slop (18 px).
const double kDragThreshold = 8;

/// A [Draggable] that starts only after the pointer moved [threshold] from where it went down.
/// Below that the press stays a plain click for the child's tap handler.
class ThresholdDraggable<T extends Object> extends Draggable<T> {
  const ThresholdDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    this.threshold = kDragThreshold,
  });

  final double threshold;

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) =>
      ThresholdMultiDragGestureRecognizer(threshold: threshold, allowedButtonsFilter: allowedButtonsFilter)
        ..onStart = onStart;
}

/// Flutter's immediate multi-drag recognizer with a minimum travel before it claims the pointer.
class ThresholdMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  ThresholdMultiDragGestureRecognizer({
    required this.threshold,
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  });

  final double threshold;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _ThresholdPointerState(event.position, event.kind, gestureSettings, threshold);

  @override
  String get debugDescription => 'threshold multidrag';
}

class _ThresholdPointerState extends MultiDragPointerState {
  _ThresholdPointerState(super.initialPosition, super.kind, super.gestureSettings, this.threshold);

  final double threshold;

  @override
  void checkForResolutionAfterMove() {
    final slop = math.max(threshold, computeHitSlop(kind, gestureSettings));
    if (pendingDelta!.distance > slop) resolve(GestureDisposition.accepted);
  }

  /// The drag starts where the pointer went down; the travel so far is applied right after, so the
  /// feedback appears under the pointer, not at the press point.
  @override
  void accepted(GestureMultiDragStartCallback starter) => starter(initialPosition);
}
