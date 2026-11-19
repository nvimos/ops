import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../state/preview.dart';
import 'theme.dart';
import 'widgets.dart';

/// The preview of the highlighted files, one under the other: text as numbered lines, a picture, a
/// PDF's first pages, or a sentence (and an Open button) for what cannot be drawn. One selection area
/// across all of it, so a drag can take lines from several files. [PreviewState] does the reading.
class PreviewPane extends StatelessWidget {
  const PreviewPane({super.key, required this.state, this.onLaunch});

  final PreviewState state;

  /// The Open button of a PDF, a picture or a program: the file, and whether it runs code.
  final void Function(String file, {bool program})? onLaunch;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PaneHeader(title: Text('Preview')),
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
    PreviewPdf(:final path) => _Pdf(path: path),
    PreviewImage(:final path) => _Picture(path: path),
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

/// The first pages of a PDF, each as wide as the pane (pdfrx, which draws with PDFium).
class _Pdf extends StatelessWidget {
  const _Pdf({required this.path});

  final String path;

  static Size _fit(Size biggest, PdfPage page, PdfPageRotation? rotation) =>
      Size(biggest.width, biggest.width * page.height / page.width);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: PdfDocumentViewBuilder.file(
      path,
      builder: (context, document) => Column(
        children: [
          for (var n = 1; n <= math.min(document?.pages.length ?? 0, PreviewPdf.maxPages); n++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PdfPageView(document: document, pageNumber: n, pageSizeCallback: _fit),
            ),
        ],
      ),
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
