import 'package:flutter/widgets.dart';

/// Whether this build renders markdown. False here: this is the stub, `make configure markdown=on`
/// swaps in the real one. The preview shows markdown as text and has no Rendered / Text switch.
const bool markdownBuiltIn = false;

/// The colours and text styles of the rendered markdown; unused by the stub.
class MarkdownLook {
  const MarkdownLook({
    required this.body,
    required this.code,
    required this.link,
    required this.muted,
    required this.codeBackground,
    required this.rule,
  });

  final TextStyle body, code;
  final Color link, muted, codeBackground, rule;
}

/// Never shown in this build ([markdownBuiltIn] is false); the source as plain text if it is.
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    required this.folder,
    required this.look,
    required this.onLink,
  });

  final String data;
  final String folder;
  final MarkdownLook look;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) => Text(data, style: look.code);
}
