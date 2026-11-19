import '../backend/models.dart';
import '../backend/repo_backend.dart';
import 'editors.dart';
import 'paths.dart';

/// The editor of a local session: the one Settings detected or the user chose, started as a program
/// of its own. It opens a file at a line; it has no cursor to report and cannot show a revision.
class ExternalEditor implements EditorSession {
  ExternalEditor(this.editors, {required this.root});

  final Editors editors;

  /// The repository's working-tree root: relative paths are opened from here.
  final String root;

  @override
  Stream<Cursor> get cursors => const Stream.empty();

  @override
  Future<void> open(String path, int line) => editors.open(file: _absolute(path), line: line);

  @override
  Future<void> show(String rev, String path, int line) async =>
      throw EditorException('Showing a file as of a revision needs the Neovim backend.');

  @override
  Future<List<String>> getText(int buf) async =>
      throw EditorException('Buffers belong to Neovim; there are none here.');

  String _absolute(String path) {
    final clean = path.replaceAll(r'\', '/');
    final absolute = clean.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(clean);
    return absolute ? clean : pathIn(root, clean);
  }
}
