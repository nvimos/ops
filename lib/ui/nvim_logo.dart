import 'package:material_ui/material_ui.dart';

/// Neovim's mark at icon size: the green left bar, the blue right bar and the diagonal between them,
/// drawn so it needs no asset or package.
class NvimLogo extends StatelessWidget {
  const NvimLogo({super.key, this.size = 12, this.dimmed = false});

  final double size;

  /// Drawn faint (not connected).
  final bool dimmed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _NvimLogoPainter(dimmed: dimmed)),
  );
}

class _NvimLogoPainter extends CustomPainter {
  const _NvimLogoPainter({required this.dimmed});

  final bool dimmed;

  static const _green = Color(0xFF6DB33F);
  static const _darkGreen = Color(0xFF4E8A2B);
  static const _blue = Color(0xFF2F8FD8);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final alpha = dimmed ? 0.4 : 1.0;
    Paint fill(Color c) => Paint()..color = c.withValues(alpha: alpha);
    // the left bar, slanted on top as in the logo
    canvas.drawPath(
      Path()
        ..moveTo(0.08 * w, 0.22 * h)
        ..lineTo(0.36 * w, 0.0)
        ..lineTo(0.36 * w, h)
        ..lineTo(0.08 * w, 0.78 * h)
        ..close(),
      fill(_green),
    );
    // the right bar
    canvas.drawPath(
      Path()
        ..moveTo(0.64 * w, 0.0)
        ..lineTo(0.92 * w, 0.22 * h)
        ..lineTo(0.92 * w, 0.78 * h)
        ..lineTo(0.64 * w, h)
        ..close(),
      fill(_blue),
    );
    // the diagonal from the top of the left bar to the bottom of the right one
    canvas.drawPath(
      Path()
        ..moveTo(0.36 * w, 0.0)
        ..lineTo(0.50 * w, 0.0)
        ..lineTo(0.78 * w, h)
        ..lineTo(0.64 * w, h)
        ..close(),
      fill(_darkGreen),
    );
  }

  @override
  bool shouldRepaint(_NvimLogoPainter old) => old.dimmed != dimmed;
}
