/// Where a link in a rendered document goes: the preview follows it like a small browser.
library;

import 'package:path/path.dart' as p;

import 'preview_adapters.dart' show DocumentAdapter;

/// What a tapped link means.
sealed class PreviewLink {
  const PreviewLink();
}

/// A web address (or mail): the system opens it.
class WebLink extends PreviewLink {
  const WebLink(this.url);

  final String url;
}

/// Another document (markdown or HTML): the preview shows it. [path] is relative to the repo when
/// it is inside it, else absolute, as [PreviewState.load] takes it.
class DocumentLink extends PreviewLink {
  const DocumentLink(this.path);

  final String path;
}

/// Any other local file: opened the way the preview's Open button opens one. [path] is absolute.
class FileLink extends PreviewLink {
  const FileLink(this.path);

  final String path;
}

/// What [href], written in the document at [from] (absolute), points at; null for a link that stays
/// in the document (`#heading`) or that cannot be read.
PreviewLink? resolveLink(String href, {required String from, required String root}) {
  final raw = href.trim();
  final drive = _drive.hasMatch(raw);
  final uri = drive ? null : Uri.tryParse(raw);
  if (!drive && uri == null) return null;
  if (uri != null && uri.hasScheme && uri.scheme != 'file') return WebLink(uri.toString());
  final target = switch (uri) {
    null => raw.split('#').first.replaceAll(r'\', '/'),
    // An HTML page's links come resolved against its folder; `#part` alone ends in that folder.
    Uri(scheme: 'file') when uri.path.endsWith('/') => '',
    Uri(scheme: 'file') => Uri(scheme: 'file', path: uri.path).toFilePath(windows: true).replaceAll(r'\', '/'),
    _ => Uri.decodeComponent(uri.path),
  };
  if (target.isEmpty) return null;
  final absolute = _posix.normalize(
    _drive.hasMatch(target) || target.startsWith('/') ? target : _posix.join(_posix.dirname(_slashes(from)), target),
  );
  if (DocumentAdapter.kindOf(absolute) == null) return FileLink(absolute);
  final base = _slashes(root).replaceFirst(RegExp(r'/+$'), '');
  final inside = absolute.toLowerCase().startsWith('${base.toLowerCase()}/');
  return DocumentLink(inside ? absolute.substring(base.length + 1) : absolute);
}

final _drive = RegExp(r'^[A-Za-z]:[\\/]');
final _posix = p.Context(style: p.Style.posix);
String _slashes(String path) => path.replaceAll(r'\', '/');
