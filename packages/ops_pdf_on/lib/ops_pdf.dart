import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// Whether this build draws PDF pages. True here: the real one, with pdfrx (PDFium).
const bool pdfBuiltIn = true;

/// The first [maxPages] pages of the PDF at [path], each as wide as the pane.
class PdfPages extends StatelessWidget {
  const PdfPages({super.key, required this.path, required this.maxPages, this.style});

  final String path;
  final int maxPages;

  /// Unused here; the stub draws its sentence in it.
  final TextStyle? style;

  static Size _fit(Size biggest, PdfPage page, PdfPageRotation? rotation) =>
      Size(biggest.width, biggest.width * page.height / page.width);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: PdfDocumentViewBuilder.file(
      path,
      builder: (context, document) => Column(
        children: [
          for (var n = 1; n <= math.min(document?.pages.length ?? 0, maxPages); n++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PdfPageView(document: document, pageNumber: n, pageSizeCallback: _fit),
            ),
        ],
      ),
    ),
  );
}
