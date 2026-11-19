import 'dart:async';

import 'models.dart';

/// What to do with uncommitted changes to tracked files when switching branches.
enum CheckoutHow {
  /// Stash them first.
  stash,

  /// Throw them away.
  force,
}

/// An event from a backend, in seq order per domain. A resync shows up as reason 'snapshot' with
/// the domain's full snapshot in [data].
class NvimEvent {
  NvimEvent(this.domain, this.reason, this.seq, this.data);
  final String domain, reason;
  final int seq;
  final Map<String, Object?> data;

  @override
  String toString() => 'NvimEvent($domain#$seq $reason)';
}

class StartDirs {
  StartDirs(Map<String, Object?> m) : source = str(m['source']), dirs = asList(m['dirs']).map(str).toList();

  /// 'startdirs' (genja-startdirs) or 'oldfiles' (dirs of recent files).
  final String source;
  final List<String> dirs;
}

/// The repository operations the modes use: git, merges with conflicts, files, jobs, start
/// directories and tracking. Implemented by `NvimBackend` (the relay plugin); a local
/// implementation follows. No editor in here: see [EditorSession].
abstract interface class RepoBackend {
  /// What [rebase] returns when there was nothing to do.
  static const upToDate = 'up-to-date';

  /// Repository hints (`git` domain) and job events (`jobs` domain), in seq order per domain.
  Stream<NvimEvent> get events;

  /// Completes when the backend is gone (connection closed).
  Future<void> get done;
  Future<void> close();

  // Git ---------------------------------------------------------------------------------------

  Future<Branches> branches();
  Future<List<Commit>> log(String base, String head);
  Future<PrDiff> diff(String base, String head);
  Future<Status> status();
  Future<DiffFile?> diffFile(String path, {required bool staged});
  Future<void> stage(String path);
  Future<void> unstage(String path);
  Future<void> discard(String path);
  Future<void> stageHunk(String path, Hunk h);
  Future<void> unstageHunk(String path, Hunk h);
  Future<void> discardHunk(String path, Hunk h);

  /// Switch branches. With changes in the way, [how] says what to do with them (see [CheckoutHow]).
  Future<void> checkout(String branch, {CheckoutHow? how});

  /// Merge [head] into the local branch [base] with a merge commit; returns the new HEAD's sha.
  Future<String> merge(String base, String head);

  /// Rebase the local branch [head] onto [base]; returns the new HEAD's sha, or [upToDate] when
  /// there was nothing to do.
  Future<String> rebase(String base, String head);
  Future<String> commit(String message);

  /// Merges with conflicts, finished in a worktree of their own. Indexes are 0-based here.
  Future<List<String>> mergePreflight(String base, String head);
  Future<MergeStart> mergeStart(String base, String head);
  Future<List<String>> mergeUnmerged(String path);
  Future<List<ConflictHunk>> mergeHunks(String path, String file);
  Future<void> mergePick(String path, String file, int index, String side);
  Future<void> mergeAdd(String path, String file);
  Future<String> mergeFinish(String base, String head, String path);
  Future<void> mergeAbort(String path);

  // Files (Tasks mode) ------------------------------------------------------------------------

  Future<List<FileEntry>> listFiles(List<String> dirs);
  Future<List<FileText>> readFiles(List<String> paths);
  Future<void> setLines(String path, List<LineEdit> edits);
  Future<void> move(String from, String to);
  Future<void> create(String path, List<String> lines);

  // Jobs --------------------------------------------------------------------------------------

  /// Start claude / openspec / backlog without blocking; returns the job id. Its end comes as a
  /// `jobs` `finished` event.
  Future<int> startJob(String cmd, List<String> args, {String? stdin, String? label});
  Future<void> cancelJob(int id);
  Future<CliResult> cli(String cmd, List<String> args);

  // Directories and tracking -------------------------------------------------------------------

  /// The start dirs to pick from: genja-startdirs' frecency order, else the dirs of recent files.
  Future<StartDirs> dirs();

  /// Make [path] the working directory; returns the new one. The git domain follows with a new
  /// snapshot.
  Future<String> cd(String path);

  /// Where the repo's planning lives: the repo root, or the folder its `.nvimos` names.
  Future<Tracking> tracking();

  /// Where the backend plugin lives, to start another Neovim with it; null when there is none.
  Future<String?> pluginRoot();
}

/// The editor the repository belongs to, when there is one. A session without an editor holds
/// null, so a mode cannot call [open] or [show] without checking.
abstract interface class EditorSession {
  /// The live cursor (`windows` domain).
  Stream<Cursor> get cursors;

  /// Edit a working-tree file (relative to the repo root) at a 1-based line.
  Future<void> open(String path, int line);

  /// Show a file as it is on [rev] in a read-only buffer, at a 1-based line.
  Future<void> show(String rev, String path, int line);

  /// The lines of buffer [buf].
  Future<List<String>> getText(int buf);
}
