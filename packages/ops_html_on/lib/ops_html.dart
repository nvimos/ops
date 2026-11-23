import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

/// Whether this build renders HTML. True here; `make configure html=off` swaps in the stub.
const bool htmlBuiltIn = true;

/// One HTML document, drawn as Flutter widgets: tags and basic CSS, no JavaScript, no web
/// requests. As tall as its content (the pane scrolls); the text takes part in the surrounding
/// `SelectionArea`. Relative links and pictures resolve against [folder]; [onLink] gets every
/// tapped link, already resolved (`file:///...` for a local one).
class HtmlView extends StatelessWidget {
  const HtmlView({super.key, required this.html, required this.folder, required this.style, required this.onLink});

  final String html;
  final String folder;
  final TextStyle style;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) => HtmlWidget(
    html,
    baseUrl: Uri.directory(folder, windows: true),
    textStyle: style,
    buildAsync: false,
    customWidgetBuilder: _noWebPicture,
    onTapUrl: (url) {
      onLink(url);
      return true;
    },
  );

  /// A picture from the web is not fetched: a local page must not reach out. Its alt text stands in.
  Widget? _noWebPicture(dom.Element element) {
    if (element.localName != 'img') return null;
    final src = element.attributes['src'] ?? '';
    if (!src.startsWith('http:') && !src.startsWith('https:') && !src.startsWith('//')) return null;
    return Text(element.attributes['alt'] ?? src, style: style.copyWith(fontStyle: FontStyle.italic));
  }
}
