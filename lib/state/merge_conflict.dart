import 'dart:io';

import '../backend/models.dart';

/// A merge that stopped with conflicts, in its worktree (nvimos/merge.lua): the files, which of them
/// are still unresolved, the file open and its hunks. The main checkout is not part of it.
class MergeConflict {
  MergeConflict({required this.base, required this.head, required this.path, required this.files})
    : unresolved = List.of(files);

  final String base, head;

  /// The worktree the merge is in.
  final String path;

  /// Every conflicted file, as the pre-flight named them.
  final List<String> files;

  /// The files that still have conflicts or are not yet marked resolved.
  List<String> unresolved;

  /// The file open in the conflict view, and its hunks.
  String? file;
  List<ConflictHunk> hunks = const [];
}

/// Open a conflicted file in a new nvim-qt window (not in diff mode). Returns the error text, or null.
Future<String?> openInNvimQt(String fullPath) async {
  try {
    await Process.start('nvim-qt', [fullPath], mode: ProcessStartMode.detached);
    return null;
  } on ProcessException catch (e) {
    return 'nvim-qt did not start: ${e.message}';
  }
}
