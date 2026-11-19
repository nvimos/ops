import 'dart:async';
import 'dart:io';

/// What changed since the last signal.
class RepoChange {
  RepoChange({required this.paths, required this.refs, required this.index});

  /// Working-tree files (relative, forward slashes) that were written, created or deleted.
  final Set<String> paths;

  /// HEAD, a branch or tag, a rebase or merge in progress, or another worktree's HEAD changed.
  final bool refs;

  /// The index changed (a stage, unstage or commit, here or in a terminal).
  final bool index;
}

/// The one watcher of a local repository: the working tree and the files in `.git` that say
/// something happened (`HEAD`, `index`, `refs/`, `packed-refs`, each worktree's `HEAD` and `index`,
/// merge and rebase state). Changes arrive as one [RepoChange] after the burst is over, so a
/// checkout or a rebase gives one reload, not one per file. `.git/objects` and build folders are
/// left out. The Changes views reload on it, and so does the History mode's stack: it is the
/// repository's ref watcher, not a second one.
class RepoWatcher {
  /// Starts watching [root] now. [debounce] is how long the tree must stay quiet; [maxWait] caps
  /// it, so a build that never stops writing still refreshes. [watch] is the source of file
  /// events (the directory's own by default); [ignored] says more about a working-tree path.
  RepoWatcher(
    String root, {
    this.debounce = const Duration(milliseconds: 150),
    this.maxWait = const Duration(seconds: 1),
    Stream<FileSystemEvent> Function(String dir)? watch,
    this.ignored,
  }) : root = _slashes(root) {
    final source = watch ?? (dir) => Directory(dir).watch(recursive: true);
    _subs.add(source(root).listen(_onEvent, onError: (_) {}));
    final gitdir = _linkedGitDir(root);
    if (gitdir != null) _subs.add(source(gitdir).listen((e) => _onEvent(e, gitDir: gitdir), onError: (_) {}));
  }

  final String root;
  final Duration debounce, maxWait;
  final bool Function(String relative)? ignored;

  final _out = StreamController<RepoChange>.broadcast();
  final _subs = <StreamSubscription<FileSystemEvent>>[];
  final _paths = <String>{};
  bool _refs = false, _index = false;
  Timer? _timer;
  DateTime? _first;
  bool _closed = false;

  Stream<RepoChange> get changes => _out.stream;

  /// Folders whose contents are not the user's work: dependency and build output.
  static const quietFolders = {
    'node_modules', 'build', '.dart_tool', 'out', 'target', 'dist', '__pycache__', '.gradle', '.idea',
  };

  void _onEvent(FileSystemEvent e, {String? gitDir}) {
    if (_closed) return;
    final path = _slashes(e.path);
    final base = gitDir == null ? root : _slashes(gitDir);
    if (!path.startsWith(base)) return;
    final rel = path.substring(base.length).replaceFirst(RegExp(r'^/'), '');
    if (rel.isEmpty) return;
    if (gitDir != null) return _gitFile(rel);
    if (rel == '.git' || rel.startsWith('.git/')) return _gitFile(rel.substring(rel.length == 4 ? 4 : 5));
    if (_quiet(rel)) return;
    _paths.add(rel);
    _soon();
  }

  /// [rel] is inside the git dir. Only the files that move when git state moves count.
  void _gitFile(String rel) {
    if (rel.endsWith('.lock')) return;
    final parts = rel.split('/');
    if (rel == 'index') {
      _index = true;
    } else if (rel == 'HEAD' || rel == 'packed-refs' || rel == 'MERGE_HEAD' || rel == 'CHERRY_PICK_HEAD' || rel == 'REBASE_HEAD') {
      _refs = true;
    } else if (parts.first == 'refs' || parts.first == 'rebase-merge' || parts.first == 'rebase-apply') {
      _refs = true;
    } else if (parts.first == 'worktrees' && parts.length == 3 && (parts[2] == 'HEAD' || parts[2] == 'index')) {
      parts[2] == 'HEAD' ? _refs = true : _index = true;
    } else {
      return;
    }
    _soon();
  }

  bool _quiet(String rel) {
    for (final part in rel.split('/')) {
      if (quietFolders.contains(part)) return true;
    }
    return ignored?.call(rel) ?? false;
  }

  void _soon() {
    _first ??= DateTime.now();
    final waited = DateTime.now().difference(_first!);
    _timer?.cancel();
    final left = maxWait - waited;
    _timer = Timer(left < debounce ? (left.isNegative ? Duration.zero : left) : debounce, _flush);
  }

  void _flush() {
    _timer = null;
    _first = null;
    if (_closed) return;
    final change = RepoChange(paths: {..._paths}, refs: _refs, index: _index);
    _paths.clear();
    _refs = _index = false;
    _out.add(change);
  }

  /// The branch HEAD names, or null on a detached HEAD or when it cannot be read.
  String? head() {
    final gitdir = _linkedGitDir(root) ?? '$root/.git';
    try {
      final text = File('$gitdir/HEAD').readAsStringSync().trim();
      const prefix = 'ref: refs/heads/';
      return text.startsWith(prefix) ? text.substring(prefix.length) : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Stops watching; nothing is delivered afterwards.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _out.close();
  }

  /// A linked worktree has a `.git` file that names its git dir (outside the tree).
  static String? _linkedGitDir(String root) {
    final file = File('$root/.git');
    try {
      if (!file.existsSync()) return null;
      final line = file.readAsStringSync().trim();
      const prefix = 'gitdir:';
      return line.startsWith(prefix) ? _slashes(line.substring(prefix.length).trim()) : null;
    } on FileSystemException {
      return null;
    }
  }

  static String _slashes(String p) => p.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
}
