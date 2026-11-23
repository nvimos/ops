import 'package:flutter/widgets.dart';

/// Whether this build draws PDF pages. False here: this is the stub, `make configure pdf=on` swaps in the real one.
const bool pdfBuiltIn = false;

/// The first [maxPages] pages of the PDF at [path], each as wide as the pane. The stub only says that
/// the pages are not built in; the Open button above it still opens the file.
class PdfPages extends StatelessWidget {
  const PdfPages({super.key, required this.path, required this.maxPages, this.style});

  final String path;
  final int maxPages;

  /// The text style of the stub's sentence.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Text('PDF pages are not in this build (make configure pdf=on)', style: style),
  );
}
