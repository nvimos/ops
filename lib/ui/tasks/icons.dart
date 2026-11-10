import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

Color statusColor(String s) => switch (s.toLowerCase()) {
  'to do' => C.muted,
  'in progress' => C.yellow,
  'needs test' => C.purple,
  'done' => C.accent,
  'dropped' => C.faint,
  'draft' => C.muted,
  'active' => C.yellow,
  'completed' => C.accent,
  _ => C.muted,
};

/// Linear-style status circle: empty, half, ring with dot, check, cross.
class StatusIcon extends StatelessWidget {
  const StatusIcon(this.status, {super.key, this.size = 14});

  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final c = statusColor(status);
    if (s == 'done' || s == 'completed') return Icon(Icons.check_circle, size: size + 1, color: c);
    if (s == 'dropped') return Icon(Icons.cancel, size: size + 1, color: c);
    final fill = switch (s) {
      'in progress' || 'active' => .5,
      'needs test' => .75,
      _ => 0.0,
    };
    return CustomPaint(size: Size.square(size), painter: _Ring(c, fill));
  }
}

class _Ring extends CustomPainter {
  _Ring(this.color, this.fill);
  final Color color;
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    canvas.drawCircle(
      center,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color,
    );
    if (fill > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r - 3.2),
        -pi / 2,
        2 * pi * fill,
        true,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_Ring old) => old.color != color || old.fill != fill;
}

const priorities = ['', 'low', 'medium', 'high'];

/// Linear-style priority bars; '' shows three faint dashes.
class PriorityIcon extends StatelessWidget {
  const PriorityIcon(this.priority, {super.key});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final p = priority.toLowerCase();
    if (p == 'urgent') return const Icon(Icons.priority_high, size: 14, color: C.red);
    final level = switch (p) {
      'high' => 3,
      'medium' => 2,
      'low' => 1,
      _ => 0,
    };
    return SizedBox(
      width: 14,
      height: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 1; i <= 3; i++)
            Container(
              width: 3,
              height: level == 0 ? 2 : 3.0 + i * 3,
              margin: const EdgeInsets.symmetric(horizontal: .7),
              decoration: BoxDecoration(
                color: level == 0 ? C.faint : (i <= level ? C.muted : C.border),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}
