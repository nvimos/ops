import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// A path split at its last slash (or backslash): the folder, without the slash, and the base name.
(String folder, String name) splitPath(String path) {
  final clean = path.length > 1 && (path.endsWith('/') || path.endsWith(r'\')) ? path.substring(0, path.length - 1) : path;
  final i = clean.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? ('', clean) : (clean.substring(0, i), clean.substring(i + 1));
}

/// The tail of [text] that fits [cells] monospace cells: the whole text, or `…` and as much of its end
/// as fits after it.
String fitTail(String text, int cells) {
  if (text.length <= cells) return text;
  if (cells <= 1) return '…';
  return '…${text.substring(text.length - (cells - 1))}';
}

/// The folder column of a path row, as in Purrage: right-aligned monospace in the muted colour, with
/// its trailing slash, so the base names line up down the list. The row gives it `Expanded(flex: 2)`
/// as a top-level child, so every row's column is the same width.
///
/// A folder too long for the column loses its start, not its end (`…ui/widgets/`): the part next to
/// the base name is the part that tells rows apart.
class PathFolder extends StatelessWidget {
  const PathFolder(this.folder, {super.key});

  final String folder;

  static final _style = T.code.copyWith(fontSize: 11.5, color: C.muted);

  /// The width of one monospace cell per text scaler, measured once.
  static final _cellWidths = <TextScaler, double>{};

  static double _cellWidth(TextScaler scaler) => _cellWidths.putIfAbsent(scaler, () {
    final painter = TextPainter(
      text: TextSpan(text: 'MMMMMMMMMM', style: _style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final width = painter.width / 10;
    painter.dispose();
    return width;
  });

  @override
  Widget build(BuildContext context) {
    final text = folder.isEmpty ? '' : '$folder/';
    final cell = _cellWidth(MediaQuery.textScalerOf(context));
    return LayoutBuilder(
      builder: (context, constraints) => Text(
        constraints.maxWidth.isFinite ? fitTail(text, ((constraints.maxWidth + 0.01) / cell).floor()) : text,
        textAlign: TextAlign.right,
        overflow: TextOverflow.clip,
        softWrap: false,
        maxLines: 1,
        style: _style,
      ),
    );
  }
}

/// The base name column of a path row, left-aligned; the row gives it `Expanded(flex: 3)`.
///
/// A directory passes [C.folder] (Windows Explorer's folder amber) and keeps its trailing slash, so it
/// reads as a folder at a glance.
class PathName extends StatelessWidget {
  const PathName(this.name, {super.key, this.color});

  final String name;

  /// The name's colour; null: the plain text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    name,
    overflow: TextOverflow.ellipsis,
    maxLines: 1,
    style: color == null ? T.body : T.body.copyWith(color: color),
  );
}
