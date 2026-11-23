import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:ops_html/ops_html.dart';
import 'package:ops_markdown/ops_markdown.dart';
import 'package:ops_pdf/ops_pdf.dart';

import '../state/preview.dart';
import 'theme.dart';
import 'widgets.dart';

/// The preview of the highlighted files, one under the other: text as numbered lines, a picture, a
/// PDF's first pages, or a sentence (and an Open button) for what cannot be drawn. One selection area
/// across all of it, so a drag can take lines from several files. [PreviewState] does the reading.
class PreviewPane extends StatelessWidget {
  const PreviewPane({super.key, required this.state, this.onLaunch, this.onLink, this.onRender});

  final PreviewState state;

  /// The Open button of a PDF, a picture or a program: the file, and whether it runs code.
  final void Function(String file, {bool program})? onLaunch;

  /// A link tapped in a rendered document: its href (as written in markdown, resolved to a URL in
  /// HTML), and the document's absolute path.
  final void Function(String href, String from)? onLink;

  /// The Rendered / Text switch: true for rendered documents.
  final ValueChanged<bool>? onRender;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PaneHeader(
        title: const Text('Preview'),
        trailing: [
          ListenableBuilder(
            listenable: state,
            builder: (context, _) => state.hasDocument
                ? RenderedSwitch(rendered: state.rendered, onPick: onRender ?? (v) => state.rendered = v)
                : const SizedBox.shrink(),
          ),
        ],
      ),
      Expanded(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final items = state.items;
            if (items.isEmpty) return const Empty('Nothing highlighted.');
            return SelectionArea(
              child: ListView.builder(itemCount: items.length, itemBuilder: (context, i) => _item(items[i])),
            );
          },
        ),
      ),
    ],
  );

  Widget _item(PreviewItem item) => switch (item) {
    PreviewHeader(:final path) => _Header(path: path),
    PreviewLine(:final number, :final text) => _Line(number: number, text: text),
    PreviewNote(:final text) => _Note(text: text),
    PreviewPdf(:final path) => PdfPages(path: path, maxPages: PreviewPdf.maxPages, style: T.small),
    PreviewImage(:final path) => _Picture(path: path),
    PreviewDocument(kind: DocKind.markdown, :final path, :final text) => _Markdown(path: path, text: text, onLink: onLink),
    PreviewDocument(kind: DocKind.html, :final path, :final text) => _Html(path: path, text: text, onLink: onLink),
    PreviewLaunch(:final path, :final text, :final program, :final facts) => _Launch(
      text: text,
      facts: facts,
      program: program,
      onOpen: () => onLaunch?.call(path, program: program),
    ),
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: C.surface2,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.code),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        SizedBox(width: 36, child: Text('$number', textAlign: TextAlign.right, style: T.code.copyWith(color: C.muted))),
        const SizedBox(width: 10),
        Expanded(child: Text(text.replaceAll('\t', '  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.code)),
      ],
    ),
  );
}

/// Rendered / Text for the markdown and HTML files of the preview; sits in the pane's header.
class RenderedSwitch extends StatelessWidget {
  const RenderedSwitch({super.key, required this.rendered, required this.onPick});

  final bool rendered;
  final ValueChanged<bool> onPick;

  static final _style = SegmentedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: T.small,
    padding: const EdgeInsets.symmetric(horizontal: 8),
  ).copyWith(mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click));

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(value: true, label: Text('Rendered'), tooltip: 'Show markdown and HTML files rendered'),
      ButtonSegment(value: false, label: Text('Text'), tooltip: 'Show markdown and HTML files as their text'),
    ],
    selected: {rendered},
    showSelectedIcon: false,
    style: _style,
    onSelectionChanged: (picked) => onPick(picked.first),
  );
}

/// A markdown document, rendered; its links go to [onLink] with the document's path.
class _Markdown extends StatelessWidget {
  const _Markdown({required this.path, required this.text, this.onLink});

  final String path;
  final String text;
  final void Function(String href, String from)? onLink;

  static const _look = MarkdownLook(
    body: T.body,
    code: T.code,
    link: C.accent,
    muted: C.muted,
    codeBackground: C.surface2,
    rule: C.border,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: MarkdownView(
      data: text,
      folder: File(path).parent.path,
      look: _look,
      onLink: (href) => onLink?.call(href, path),
    ),
  );
}

/// An HTML document, drawn without a browser (tags and basic CSS, no scripts); its links go to
/// [onLink] with the document's path. The Open button above it shows the page in the browser.
class _Html extends StatelessWidget {
  const _Html({required this.path, required this.text, this.onLink});

  final String path;
  final String text;
  final void Function(String href, String from)? onLink;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: HtmlView(
      html: text,
      folder: File(path).parent.path,
      style: T.body,
      onLink: (url) => onLink?.call(url, path),
    ),
  );
}

/// A picture, scaled down to the pane's width and [PreviewImage.maxHeight].
class _Picture extends StatelessWidget {
  const _Picture({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        height: PreviewImage.maxHeight,
        errorBuilder: (context, error, stack) => const Text('this picture cannot be drawn', style: T.small),
      ),
    ),
  );
}

/// A file the pane cannot draw: what it is, and the button that opens it.
class _Launch extends StatelessWidget {
  const _Launch({required this.text, required this.facts, required this.program, required this.onOpen});

  final String text;
  final List<(String, String)> facts;
  final bool program;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Facts(text: text, facts: facts)),
        SelectionContainer.disabled(
          child: Tooltip(
            message: program ? 'Start this program, as a double click would' : 'Open with the default app',
            child: SmallButton(program ? 'Run' : 'Open', icon: program ? Icons.play_arrow : Icons.open_in_new, onPressed: onOpen),
          ),
        ),
      ],
    ),
  );
}

/// The sentence about a file and, under it, its labelled facts; selectable.
class _Facts extends StatelessWidget {
  const _Facts({required this.text, required this.facts});

  final String text;
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(text, style: T.small),
      for (final (label, value) in facts)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(
            TextSpan(children: [TextSpan(text: '$label  ', style: T.small), TextSpan(text: value, style: T.code)]),
          ),
        ),
    ],
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(text, style: T.small),
  );
}
