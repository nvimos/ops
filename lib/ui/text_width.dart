import 'package:material_ui/material_ui.dart';

/// The width of one line of [text].
double textWidth(String text, TextStyle style) {
  final p = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)
    ..layout();
  return p.width;
}
