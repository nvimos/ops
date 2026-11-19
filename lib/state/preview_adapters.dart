/// The preview's adapters, one per kind of file. The order of [previewAdapters]
/// is the order they are asked in; the last one takes whatever is left.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'preview_items.dart';

/// Shortcut, PDF, program, text, then any other binary.
const List<PreviewAdapter> previewAdapters = [
  LinkAdapter(),
  ImageAdapter(),
  PdfPagesAdapter(),
  PdfAdapter(),
  ProgramAdapter(),
  TextAdapter(),
  BinaryAdapter(),
];

/// A picture Flutter can decode: the sentence with Open, then the picture itself.
class ImageAdapter extends PreviewAdapter {
  const ImageAdapter();

  static const _extensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'];

  @override
  bool accepts(PreviewSource source) => _extensions.any(source.name.endsWith);

  @override
  Future<List<PreviewItem>> render(PreviewSource source) async => [
    PreviewLaunch(source.path, 'image, ${sizeText(await source.size())}'),
    PreviewImage(source.path),
  ];
}

/// Plain text: its lines, numbered, cut at [previewMaxLines].
class TextAdapter extends PreviewAdapter {
  const TextAdapter();

  @override
  bool accepts(PreviewSource source) => !source.head.contains(0);

  @override
  Future<List<PreviewItem>> render(PreviewSource source) async {
    final bytes = source.bytes;
    final text = utf8.decode(source.cut ? Uint8List.sublistView(bytes, 0, previewLimit) : bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(text);
    return [
      for (final (index, line) in lines.take(previewMaxLines).indexed) PreviewLine(index + 1, line),
      if (source.cut || lines.length > previewMaxLines) const PreviewNote('the rest of the file is not shown'),
    ];
  }
}

bool _isPdf(PreviewSource source) => source.name.endsWith('.pdf') || source.startsWith('%PDF-'.codeUnits);

/// A PDF, drawn: the sentence with Open, then its first pages. Only when
/// Settings turn the renderer on; otherwise [PdfAdapter] takes the file.
class PdfPagesAdapter extends PreviewAdapter {
  const PdfPagesAdapter();

  @override
  bool accepts(PreviewSource source) => source.renderPdf && _isPdf(source);

  @override
  Future<List<PreviewItem>> render(PreviewSource source) async => [
        PreviewLaunch(source.path, 'PDF document, ${sizeText(await source.size())}'),
        PreviewPdf(source.path),
      ];
}

/// A PDF: what it is and how big, with Open for the default viewer.
class PdfAdapter extends PreviewAdapter {
  const PdfAdapter();

  @override
  bool accepts(PreviewSource source) => _isPdf(source);

  @override
  Future<List<PreviewItem>> render(PreviewSource source) async =>
      [PreviewLaunch(source.path, 'PDF document, ${sizeText(await source.size())}')];
}

/// An executable or installer: what it is and how big, with Run.
class ProgramAdapter extends PreviewAdapter {
  const ProgramAdapter();

  static const _elf = [0x7f, 0x45, 0x4c, 0x46];

  String? _kind(PreviewSource source) {
    if (source.name.endsWith('.exe')) return 'Windows program';
    if (source.name.endsWith('.msi')) return 'Windows installer';
    if (source.startsWith(_elf)) return 'program';
    return null;
  }

  @override
  bool accepts(PreviewSource source) => _kind(source) != null;

  @override
  Future<List<PreviewItem>> render(PreviewSource source) async =>
      [PreviewLaunch(source.path, '${_kind(source)}, ${sizeText(await source.size())}', program: true)];
}

/// Any other binary file: named, sized, and openable by the desktop's default.
class BinaryAdapter extends PreviewAdapter {
  const BinaryAdapter();

  @override
  bool accepts(PreviewSource source) => true;

  @override
  Future<List<PreviewItem>> render(PreviewSource source) async =>
      [PreviewLaunch(source.path, 'binary file, ${sizeText(await source.size())}')];
}

/// A Windows shortcut (`.lnk`): where it points, its arguments and where it
/// starts. The format is the Shell Link Binary File Format (MS-SHLLINK).
class LinkAdapter extends PreviewAdapter {
  const LinkAdapter();

  @override
  bool accepts(PreviewSource source) => source.name.endsWith('.lnk') && source.startsWith(const [0x4c, 0, 0, 0]);

  @override
  Future<List<PreviewItem>> render(PreviewSource source) async {
    final link = ShellLink.parse(source.bytes);
    if (link == null) return [PreviewLaunch(source.path, 'Windows shortcut, unreadable')];
    return [
      PreviewLaunch(
        source.path,
        'Windows shortcut',
        facts: [
          if (link.target.isNotEmpty) ('Target', link.target),
          if (link.arguments.isNotEmpty) ('Arguments', link.arguments),
          if (link.workingDir.isNotEmpty) ('Start in', link.workingDir),
          if (link.target.isEmpty && link.relativePath.isNotEmpty) ('Relative', link.relativePath),
        ],
      ),
    ];
  }
}

/// The parts of a shortcut the preview shows. Empty strings for what the file
/// does not say.
class ShellLink {
  const ShellLink({this.target = '', this.arguments = '', this.workingDir = '', this.relativePath = ''});

  final String target;
  final String arguments;
  final String workingDir;
  final String relativePath;

  /// Null when [bytes] is not a shortcut or is cut short.
  static ShellLink? parse(Uint8List bytes) {
    try {
      return _parse(bytes);
    } on RangeError {
      return null;
    }
  }

  static ShellLink? _parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 76 || data.getUint32(0, Endian.little) != 0x4c) return null;
    final flags = data.getUint32(20, Endian.little);
    bool has(int bit) => flags & (1 << bit) != 0;
    var at = 76;
    if (has(0)) at += 2 + data.getUint16(at, Endian.little);

    var target = '';
    if (has(1)) {
      target = _linkInfo(bytes, data, at);
      at += data.getUint32(at, Endian.little);
    }

    final unicode = has(7);
    String string() {
      final count = data.getUint16(at, Endian.little);
      at += 2;
      final size = unicode ? count * 2 : count;
      final raw = Uint8List.sublistView(bytes, at, at + size);
      at += size;
      return unicode ? String.fromCharCodes(Uint16List.view(Uint8List.fromList(raw).buffer)) : latin1.decode(raw);
    }

    if (has(2)) string();
    final relative = has(3) ? string() : '';
    final working = has(4) ? string() : '';
    final arguments = has(5) ? string() : '';
    return ShellLink(target: target, arguments: arguments, workingDir: working, relativePath: relative);
  }

  /// The target out of the LinkInfo block at [start]: a local path or a share.
  static String _linkInfo(Uint8List bytes, ByteData data, int start) {
    final flags = data.getUint32(start + 8, Endian.little);
    final suffix = _ansi(bytes, start + data.getUint32(start + 24, Endian.little));
    if (flags & 1 != 0) {
      return _ansi(bytes, start + data.getUint32(start + 16, Endian.little)) + suffix;
    }
    if (flags & 2 != 0) {
      final network = start + data.getUint32(start + 20, Endian.little);
      final share = _ansi(bytes, network + data.getUint32(network + 8, Endian.little));
      return suffix.isEmpty ? share : '$share\\$suffix';
    }
    return suffix;
  }

  /// A NUL-terminated ANSI string at [offset].
  static String _ansi(Uint8List bytes, int offset) {
    var end = offset;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    return latin1.decode(Uint8List.sublistView(bytes, offset, end));
  }
}
