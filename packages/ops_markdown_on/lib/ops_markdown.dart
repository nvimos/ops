import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Whether this build renders markdown. True here; `make configure markdown=off` swaps in the stub.
const bool markdownBuiltIn = true;

/// The colours and text styles of the rendered markdown, from the app's theme.
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

/// One markdown document, rendered and as tall as its content (the pane scrolls). The text takes
/// part in the surrounding `SelectionArea`. [onLink] gets every tapped link's href as written;
/// relative pictures are read from [folder].
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
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    styleSheet: _sheet(look),
    extensionSet: md.ExtensionSet.gitHubFlavored,
    onTapLink: (text, href, title) {
      if (href != null) onLink(href);
    },
    imageBuilder: _picture,
  );

  /// A picture from the repo, relative to the document; a web picture is not fetched, its alt text
  /// stands in.
  Widget _picture(Uri uri, String? title, String? alt) {
    final stand = Text(alt ?? uri.toString(), style: look.body.copyWith(color: look.muted));
    if (uri.scheme == 'http' || uri.scheme == 'https') return stand;
    final file = uri.scheme == 'file' ? File.fromUri(uri) : File('$folder/${Uri.decodeComponent(uri.path)}');
    return Image.file(file, errorBuilder: (context, error, stack) => stand);
  }
}

MarkdownStyleSheet _sheet(MarkdownLook look) {
  final body = look.body;
  TextStyle heading(double scale) => body.copyWith(fontSize: (body.fontSize ?? 14) * scale, fontWeight: FontWeight.w600);
  return MarkdownStyleSheet(
    p: body,
    a: body.copyWith(color: look.link, decoration: TextDecoration.underline, decorationColor: look.link),
    h1: heading(1.6),
    h2: heading(1.35),
    h3: heading(1.15),
    h4: heading(1.0),
    h5: heading(1.0),
    h6: heading(1.0),
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    code: look.code.copyWith(backgroundColor: look.codeBackground),
    codeblockDecoration: BoxDecoration(color: look.codeBackground, borderRadius: BorderRadius.circular(4)),
    codeblockPadding: const EdgeInsets.all(8),
    blockquote: body.copyWith(color: look.muted),
    blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: look.rule, width: 3))),
    blockquotePadding: const EdgeInsets.only(left: 10),
    listBullet: body,
    tableHead: body.copyWith(fontWeight: FontWeight.w600),
    tableBody: body,
    tableBorder: TableBorder.all(color: look.rule),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: look.rule))),
    checkbox: body,
    blockSpacing: 8,
  );
}
