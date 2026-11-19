import 'dart:io';

import 'package:flutter/foundation.dart';

import '../backend/repo_backend.dart';
import '../backend/models.dart';
import 'diff_prefs.dart';

/// Runs a backend action; returns the error text, or null (Session.run).
typedef RunAction = Future<String?> Function(Future<void> Function(RepoBackend b) action);

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

/// What a merge did: an error, a note for the user, and whether a conflict view is now open.
class MergeResult {
  const MergeResult({this.error, this.note});

  final String? error;
  final String? note;
}

/// The merges of the app, with conflicts: the pre-flight, the merge worktree, and the open conflict
/// that the conflict layout shows (in Changes and Pull request alike).
class ConflictController extends ChangeNotifier {
  ConflictController(this._run, this._prefs);

  final RunAction _run;
  final DiffPrefs _prefs;

  /// The open conflict, or null.
  MergeConflict? current;

  /// Why the open file's hunks could not be read, or null.
  String? loadError;

  /// Merge head into base. The pre-flight looks for conflicts first: without one the merge runs at
  /// once; with one, the merge is started in its worktree and the conflict layout opens.
  Future<MergeResult> merge(String base, String head) async {
    String? note;
    final err = await _run((x) async {
      if ((await x.mergePreflight(base, head)).isEmpty) {
        await x.merge(base, head);
        note = 'Merged $head into $base';
        return;
      }
      final s = await x.mergeStart(base, head);
      if (s.files.isEmpty) {
        await x.mergeFinish(base, head, s.path); // clean after all: commit it, and say so
        note = 'Merged $head into $base: no conflicts after all';
        return;
      }
      current = MergeConflict(base: base, head: head, path: s.path, files: s.files);
    });
    if (current != null) {
      _prefs.setLayout(DiffLayout.conflict);
      await openFile(current!.files.first);
    }
    notifyListeners();
    return MergeResult(error: err, note: note);
  }

  /// Run again when the conflict view opens: a conflict that is gone turns the merge into a plain one
  /// (the worktree is thrown away), and the user is told so.
  Future<MergeResult> recheck() async {
    final c = current;
    if (c == null) return const MergeResult();
    String? clean;
    final err = await _run((x) async {
      if ((await x.mergePreflight(c.base, c.head)).isNotEmpty) return;
      await x.mergeAbort(c.path);
      clean = 'The conflicts are gone: ${c.head} merges into ${c.base} without them';
    });
    if (err != null || clean == null) return MergeResult(error: err);
    current = null;
    _prefs.setLayout(DiffLayout.unified);
    final again = await merge(c.base, c.head);
    return MergeResult(error: again.error, note: clean);
  }

  Future<String?> _action(Future<void> Function(RepoBackend x, MergeConflict c) action) async {
    final c = current;
    if (c == null) return 'no merge with conflicts is open';
    final err = await _run((x) => action(x, c));
    notifyListeners();
    return err;
  }

  /// Open a conflicted file: its hunks are read again (a failure shows in the view).
  Future<String?> openFile(String file) async {
    final err = await _action((x, c) async {
      c.file = file;
      c.hunks = await x.mergeHunks(c.path, file);
    });
    loadError = err;
    notifyListeners();
    return err;
  }

  /// Take one side of hunk [index] of the open file, then read the file again.
  Future<String?> pickHunk(int index, String side) => _action((x, c) async {
    await x.mergePick(c.path, c.file!, index, side);
    c.hunks = await x.mergeHunks(c.path, c.file!);
  });

  /// Mark a file resolved (refused while it has a conflict marker).
  Future<String?> addFile(String file) => _action((x, c) async {
    await x.mergeAdd(c.path, file);
    c.unresolved = await x.mergeUnmerged(c.path);
  });

  /// Complete the merge: commit in the worktree, move base, remove the worktree.
  Future<String?> finish() async {
    final c = current;
    final err = await _action((x, _) async {
      await x.mergeFinish(c!.base, c.head, c.path);
      current = null;
    });
    if (current == null) _prefs.setLayout(DiffLayout.unified);
    notifyListeners();
    return err;
  }

  /// Throw the merge away: the worktree is removed, base is not touched.
  Future<String?> abort() async {
    final err = await _action((x, c) async {
      await x.mergeAbort(c.path);
      current = null;
    });
    if (current == null) _prefs.setLayout(DiffLayout.unified);
    notifyListeners();
    return err;
  }
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
