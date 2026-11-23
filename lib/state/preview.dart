/// The preview pane's state: the content of the highlighted files, one under
/// the other. Each file is shown by the first adapter (`preview_adapters.dart`)
/// that accepts it: text as lines, a PDF, a program or a shortcut as a sentence
/// with an Open button. A folder, a file that is gone and a file that cannot be
/// read say so in a line.
///
/// Reading goes through [FileReader], so tests need no disk.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' show isAbsolute;

import 'preview_adapters.dart';
import 'preview_items.dart';

export 'preview_items.dart';

/// The first [limit] bytes of the file at [path]; throws [FileSystemException].
/// [previewLimit] is also what decides "truncated": the reader returns one
/// byte more than that when the file is longer.
typedef FileReader = Future<Uint8List> Function(String path, int limit);

/// The real disk.
Future<Uint8List> readStart(String path, int limit) async {
  final file = await File(path).open();
  try {
    return await file.read(limit);
  } finally {
    await file.close();
  }
}

/// The size of the file at [path], in bytes.
typedef FileSizer = Future<int> Function(String path);

class PreviewState extends ChangeNotifier {
  PreviewState({
    required this.root,
    FileReader? read,
    FileSizer? size,
    this.adapters = previewAdapters,
    this.renderable = const {DocKind.markdown, DocKind.html},
  })  : _read = read ?? readStart,
        _size = size ?? ((path) => File(path).length());

  /// The repository folder the paths are relative to; asked on every load,
  /// because Browse can switch the repository.
  final String Function() root;
  final FileReader _read;
  final FileSizer _size;

  /// The file types the pane knows, asked in order.
  final List<PreviewAdapter> adapters;

  /// The document kinds this build can render (`make configure markdown=` / `html=`); a document
  /// of another kind shows as its lines in both views.
  final Set<DocKind> renderable;

  /// Draw a PDF's pages (a Settings choice); off shows a sentence and Open.
  bool renderPdf = false;

  /// At most this many bytes of a file are shown.
  static const limit = previewLimit;

  /// At most this many lines of a file are shown.
  static const maxLines = previewMaxLines;

  /// At most this many files are shown at once.
  static const maxFiles = 20;

  List<PreviewItem> _rendered = const [];
  List<PreviewItem> _text = const [];
  List<String> _paths = const [];
  int _generation = 0;
  bool _disposed = false;

  /// Documents (markdown, HTML) are drawn rendered; false shows their numbered lines. Both lists
  /// are built at load, so flipping this swaps the list and reads nothing.
  bool get rendered => _renderedView;
  bool _renderedView = true;
  set rendered(bool value) {
    if (value == _renderedView) return;
    _renderedView = value;
    notifyListeners();
  }

  /// A document this build can render is shown, so the Rendered / Text switch means something.
  bool get hasDocument => _hasDocument;
  bool _hasDocument = false;

  /// The flat list the pane draws.
  List<PreviewItem> get items => _renderedView ? _rendered : _text;

  /// The paths the last load showed, as given; a link's way back.
  List<String> get paths => _paths;

  /// Show [paths]: each file, in the order given, one under the other. A path is relative to [root],
  /// or absolute (a followed link outside the repo). A load that is overtaken by a newer one is dropped.
  Future<void> load(List<String> paths) async {
    final generation = ++_generation;
    final shown = paths.take(maxFiles).toList();
    final items = <PreviewItem>[];
    for (final path in shown) {
      items
        ..add(PreviewHeader(path))
        ..addAll(await _of(path));
      if (generation != _generation || _disposed) return;
    }
    if (paths.length > maxFiles) {
      items.add(PreviewNote('${paths.length - maxFiles} more highlighted files are not shown'));
    }
    _paths = List.unmodifiable(paths);
    bool drawn(PreviewItem item) => item is PreviewDocument && renderable.contains(item.kind);
    _rendered = [
      for (final item in items)
        if (drawn(item)) ...[
          item,
          if ((item as PreviewDocument).cut) const PreviewNote('the rest of the file is not shown'),
        ] else if (item is PreviewDocument) ...item.lines else item,
    ];
    _text = [
      for (final item in items)
        if (item is PreviewDocument) ...item.lines else item,
    ];
    _hasDocument = items.any(drawn);
    notifyListeners();
  }

  Future<List<PreviewItem>> _of(String relative) async {
    if (relative.endsWith('/')) return const [PreviewNote('folder')];
    try {
      final path = isAbsolute(relative) ? relative : '${root()}/$relative';
      final bytes = await _read(path, limit + 1);
      if (bytes.isEmpty) return const [PreviewNote('empty file')];
      final source = PreviewSource(path: path, bytes: bytes, readSize: () => _size(path), renderPdf: renderPdf);
      return await adapters.firstWhere((adapter) => adapter.accepts(source)).render(source);
    } on PathNotFoundException {
      return const [PreviewNote('not on disk')];
    } on FileSystemException catch (error) {
      return [PreviewNote('cannot be read: ${error.osError?.message ?? error.message}')];
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
