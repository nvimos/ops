import 'package:flutter/widgets.dart';

/// Whether this build renders HTML. False here: this is the stub, `make configure html=on` swaps in
/// the real one. The preview shows HTML as text and has no Rendered / Text switch for it.
const bool htmlBuiltIn = false;

/// Never shown in this build ([htmlBuiltIn] is false); the source as plain text if it is.
class HtmlView extends StatelessWidget {
  const HtmlView({super.key, required this.html, required this.folder, required this.style, required this.onLink});

  final String html;
  final String folder;
  final TextStyle style;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) => Text(html, style: style);
}
