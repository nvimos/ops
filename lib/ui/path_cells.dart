import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// A path split at its last slash (or backslash): the folder, without the slash, and the base name.
(String folder, String name) splitPath(String path) {
  final clean = path.length > 1 && (path.endsWith('/') || path.endsWith(r'\')) ? path.substring(0, path.length - 1) : path;
  final i = clean.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? ('', clean) : (clean.substring(0, i), clean.substring(i + 1));
}

/// The folder column of a path row, as in Purrage: right-aligned monospace in the muted colour, with
/// its trailing slash, so the base names line up down the list. The row gives it `Expanded(flex: 2)`
/// as a top-level child, so every row's column is the same width.
class PathFolder extends StatelessWidget {
  const PathFolder(this.folder, {super.key});

  final String folder;

  @override
  Widget build(BuildContext context) => Text(
    folder.isEmpty ? '' : '$folder/',
    textAlign: TextAlign.right,
    overflow: TextOverflow.ellipsis,
    maxLines: 1,
    style: T.code.copyWith(fontSize: 11.5, color: C.muted),
  );
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
