/// What the preview pane draws, and the contract of the adapters that make it.
///
/// A file goes to the first [PreviewAdapter] that accepts it; the adapter turns
/// its bytes into items. A new file type is a new adapter in
/// `preview_adapters.dart`, not a branch in the state.
library;

import 'dart:typed_data';

/// At most this many bytes of a file are read for the preview. One byte more is
/// asked for, which is how "cut off" is told.
const previewLimit = 256 * 1024;

/// At most this many lines of a file are shown.
const previewMaxLines = 2000;

/// A file is binary when a NUL is in its first bytes.
const previewSniff = 8000;

/// One line of the flat preview list.
sealed class PreviewItem {
  const PreviewItem();
}

/// The file's path, above its lines.
class PreviewHeader extends PreviewItem {
  const PreviewHeader(this.path);

  final String path;
}

/// One line of text with its number.
class PreviewLine extends PreviewItem {
  const PreviewLine(this.number, this.text);

  final int number;
  final String text;
}

/// A sentence in the file's place: "folder", "cut off here".
class PreviewNote extends PreviewItem {
  const PreviewNote(this.text);

  final String text;
}

/// A file the pane cannot draw as text but the desktop can open: a sentence
/// about it, optional labelled [facts] (a shortcut's target), and an Open
/// button. [path] is absolute.
class PreviewLaunch extends PreviewItem {
  const PreviewLaunch(this.path, this.text, {this.program = false, this.facts = const []});

  final String path;
  final String text;

  /// Runs code (an executable or installer) rather than showing a document.
  final bool program;

  /// `(label, value)` pairs under the sentence, e.g. `Target`, `Start in`.
  final List<(String, String)> facts;
}

/// The first pages of a PDF, drawn by the renderer (Settings turns it on).
/// [path] is absolute.
class PreviewPdf extends PreviewItem {
  const PreviewPdf(this.path);

  final String path;

  /// At most this many pages of a document are drawn.
  static const maxPages = 5;
}

/// A picture, drawn as wide as the pane (at most [maxHeight] tall). [path] is absolute.
class PreviewImage extends PreviewItem {
  const PreviewImage(this.path);

  final String path;

  static const maxHeight = 360.0;
}

/// What kind of document a [PreviewDocument] is, so the pane picks its renderer.
enum DocKind { markdown, html }

/// A markdown or HTML document: drawn rendered, or as its numbered [lines] when the preview shows
/// text. [path] is absolute; [text] is what was read (cut at [previewLimit]).
class PreviewDocument extends PreviewItem {
  const PreviewDocument(this.kind, this.path, this.text, this.lines, {this.cut = false});

  final DocKind kind;
  final String path;
  final String text;

  /// The file is longer than what was read; the rendered view says so under the document.
  final bool cut;

  /// The text view of the same file, as [TextAdapter] draws it (with its cut-off note).
  final List<PreviewItem> lines;
}

/// What an adapter is given: the file's start and a way to ask its full size.
class PreviewSource {
  PreviewSource({required this.path, required this.bytes, required this.readSize, this.renderPdf = false});

  /// Settings allow drawing PDF pages.
  final bool renderPdf;

  /// Absolute path.
  final String path;

  /// The first [previewLimit] bytes, plus one when the file is longer.
  final Uint8List bytes;

  /// Asks the disk for the full size.
  final Future<int> Function() readSize;

  /// More than [previewLimit] bytes were there.
  bool get cut => bytes.length > previewLimit;

  /// The first [previewSniff] bytes.
  Uint8List get head => bytes.length < previewSniff ? bytes : Uint8List.sublistView(bytes, 0, previewSniff);

  /// The file name in lower case, for extension tests.
  String get name => path.toLowerCase();

  /// The file's size in bytes: free when it was all read, else asked of the disk.
  Future<int> size() async => cut ? readSize() : bytes.length;

  /// Whether the file starts with [magic].
  bool startsWith(List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}

/// One file type's way to show itself.
abstract class PreviewAdapter {
  const PreviewAdapter();

  /// Whether this adapter shows [source]; the first that does wins.
  bool accepts(PreviewSource source);

  /// The items under the file's header.
  Future<List<PreviewItem>> render(PreviewSource source);
}

/// `340 KB`, `1.2 MB`: the size a person reads.
String sizeText(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
