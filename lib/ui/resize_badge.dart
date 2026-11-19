import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Debug only: while a pane's edge is dragged, its size (`width X height`, in px) sits in the
/// middle of the pane, so a resize can be judged against the sizes the layout uses.
///
/// [dragging] turns it on at drag start and off at the end. Only this label listens to it: the
/// pane and its content are relaid as usual, never rebuilt for the badge.
class ResizeBadge extends StatelessWidget {
  const ResizeBadge({super.key, required this.width, required this.height, required this.dragging});

  final double width, height;
  final ValueListenable<bool> dragging;

  /// A dark blue behind orange digits: readable over the app's dark surfaces and the code panes.
  static const background = Color(0xFF12305C);
  static const numbers = Color(0xFFFFA53D);

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: dragging,
        builder: (context, on, _) => on
            ? Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: numbers.withValues(alpha: .4)),
                  ),
                  child: Text(
                    '${width.round()} X ${height.round()}',
                    style: T.code.copyWith(color: numbers, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
