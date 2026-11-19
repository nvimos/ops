import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../timing/ui_timing.dart';
import 'paths.dart';
import 'system.dart';

/// The host's path rules for this file's own string work.
final p.Context _paths = hostPaths;

/// One directory the walk opened, kept when it was slow or wide.
class ScanSample {
  const ScanSample({required this.path, required this.took, required this.entries});

  final String path;
  final Duration took;
  final int entries;
}

/// What one scan did, for the console: how far it went, what it skipped, and
/// which directories cost the most, so the skip list can be tuned from evidence.
class ScanReport {
  const ScanReport({
    required this.directory,
    required this.depth,
    required this.visited,
    required this.found,
    required this.skipped,
    required this.elapsed,
    required this.slowest,
    required this.widest,
    required this.stopped,
    this.appDataTrees = 0,
  });

  final String directory;
  final int depth;
  final int visited;
  final int found;
  final int skipped;
  final Duration elapsed;
  final List<ScanSample> slowest;
  final List<ScanSample> widest;
  final bool stopped;

  /// `AppData` folders met; each is walked only [RepoBrowser.appDataDepth] deep.
  final int appDataTrees;

  String get summary =>
      'scanned $directory  ${_ms(elapsed)}  depth $depth  '
      '$visited dir(s), $found repo(s)'
      '${skipped > 0 ? ', $skipped skipped' : ''}'
      '${stopped ? ', stopped at the limit' : ''}';

  String get detail {
    final lines = <String>[
      'origin: RepoBrowser.scan -> Directory.list',
      'root: $directory',
      'depth: $depth',
      'directories visited: $visited',
      'directories skipped by rule: $skipped',
      'repositories found: $found',
      'elapsed: ${_ms(elapsed)}',
      if (appDataTrees > 0)
        'AppData folders met: $appDataTrees (each walked ${RepoBrowser.appDataDepth} levels in)',
    ];
    if (slowest.isNotEmpty) {
      lines.add('slowest listings:');
      for (final sample in slowest) {
        lines.add('  ${_ms(sample.took).padLeft(8)}  ${sample.entries} entries  ${sample.path}');
      }
    }
    if (widest.isNotEmpty) {
      lines.add('widest directories:');
      for (final sample in widest) {
        lines.add('  ${sample.entries.toString().padLeft(6)} entries  ${_ms(sample.took).padLeft(8)}  ${sample.path}');
      }
    }
    return lines.join('\n');
  }

  static String _ms(Duration duration) => duration.inMilliseconds < 1000
      ? '${duration.inMilliseconds} ms'
      : '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
}

/// Finds the repositories under a directory, for the Browse mode.
///
/// A repository is a directory holding a `.git` (a folder for a clone, a file for
/// a worktree or submodule); the entry points at that working directory, never at
/// `.git` itself. The walk gives up at [maxDepth], never follows a link, and stops
/// at the first repository it meets on a branch — a repository's own subfolders
/// are not offered as separate checkouts.
class RepoBrowser extends ChangeNotifier {
  RepoBrowser({
    required String startDirectory,
    this.maxDepth = depthDefault,
    this.onReport,
    this.lister = const SystemDirectoryLister(),
    Env? env,
  })  : _directory = _clean(startDirectory),
        isWindows = (env ?? Env.system()).isWindows;

  /// The file system the walk reads.
  final DirectoryLister lister;

  /// The skip trees are Windows system paths; elsewhere the walk has none.
  final bool isWindows;

  /// How many levels below the browsed directory the walk goes (a setting;
  /// [depthDefault] until Settings says otherwise).
  int maxDepth;

  static const depthMin = 1;
  static const depthMax = 12;
  static const depthDefault = 5;

  /// Settings changed the depth: walk again with it, replacing a walk that is
  /// still running with the old one.
  Future<void> useDepth(int depth) {
    final next = depth.clamp(depthMin, depthMax);
    if (next == maxDepth) return _running ?? Future.value();
    maxDepth = next;
    return _start(empty: false, force: true);
  }

  /// Called once per scan, for the console.
  void Function(ScanReport report)? onReport;

  /// Folders that never hold the checkout the user wants, and would dominate the
  /// walk on a home directory. Lower case; the comparison lower-cases the name.
  static const skip = {
    '.git',
    'node_modules',
    '.dart_tool',
    '.venv',
    'venv',
    'build',
    'target',
    'dist',
    '.gradle',
    '.idea',
    '.vscode',
    '.cache',
    'obj',
    'bin',
    'out',
    'coverage',
    '.next',
    '.turbo',
    '.terraform',
    'vendor',
    'pods',
    '__pycache__',
    '.npm',
    '.pnpm-store',
    '.nuget',
    '.rustup',
    '.cargo',
  };

  /// How far below an `AppData` folder the walk may go. It is not skipped — a
  /// stray checkout can live there — but three levels of caches per application
  /// are not worth the enumeration.
  static const appDataDepth = 2;

  /// Whole trees never worth walking on Windows: no checkout lives there, and the
  /// enumeration cost is enormous. Matched as path prefixes, case-insensitively.
  static const skipTrees = [
    'c:/windows',
    'c:/program files',
    'c:/program files (x86)',
    'c:/programdata',
    r'c:/$recycle.bin',
    'c:/system volume information',
    'c:/recovery',
    'c:/perflogs',
  ];

  /// A ceiling on how many directories one scan will open. Five levels below a
  /// drive root can still be enormous; the user can narrow the folder instead.
  static const maxDirectories = 20000;

  String get directory => _directory;
  String _directory;

  set directory(String value) => _directory = _clean(value);

  List<String> repos = const [];
  bool scanning = false;
  String? error;

  String _filter = '';
  int _index = 0;

  /// The `/` filter of the Browse list: a case-insensitive part of the path.
  String get filter => _filter;

  /// The repositories the list shows: [repos] narrowed by [filter].
  List<String> get visible {
    if (_filter.isEmpty) return repos;
    final needle = _filter.toLowerCase();
    return [
      for (final repo in repos)
        if (repo.toLowerCase().contains(needle)) repo,
    ];
  }

  /// The keyboard cursor in [visible], kept inside it.
  int get index {
    final count = visible.length;
    return count == 0 ? 0 : _index.clamp(0, count - 1);
  }

  /// The repository under the cursor, for Enter.
  String? get selected {
    final shown = visible;
    return shown.isEmpty ? null : shown[index];
  }

  void setFilter(String query) {
    if (query == _filter) return;
    _filter = query;
    _index = 0;
    notifyListeners();
  }

  /// Move the cursor by [delta] rows, clamped; Home/End are large deltas.
  void move(int delta) {
    final count = visible.length;
    if (count == 0) return;
    final next = (index + delta).clamp(0, count - 1);
    if (next == index) return;
    _index = next;
    notifyListeners();
  }

  /// Bumped by every walk that starts; a walk whose number is no longer current
  /// stops at its next step, so `up` or a drive click never waits for it.
  int _generation = 0;

  /// The directory the running walk started from.
  String? _walking;

  /// How often found repositories are published while a walk runs.
  static const publishEvery = Duration(milliseconds: 100);

  static String _clean(String path) => canonicalPath(path);

  bool _inSkippedTree(String path) {
    if (!isWindows) return false;
    final lower = _clean(path).toLowerCase();
    for (final tree in skipTrees) {
      if (lower == tree || lower.startsWith('$tree/')) return true;
    }
    return false;
  }

  /// True for a path that sits inside a `.git` folder, in any casing.
  static bool _belowGitDir(String path) {
    for (final segment in _clean(path).split('/')) {
      if (segment.toLowerCase() == '.git') return true;
    }
    return false;
  }

  /// Drop an entry the user tried to open and git refused, so the list stops
  /// offering a checkout that is gone or was never one.
  void drop(String path) {
    final before = repos.length;
    repos = [
      for (final repo in repos)
        if (repo != path) repo,
    ];
    if (repos.length != before) notifyListeners();
  }

  /// Go one level up and scan there. At a root (`C:/`, `/`) there is nowhere up.
  Future<void> up() async {
    final parent = _paths.dirname(directory);
    if (parent == directory) return;
    await goTo(canonicalPath(parent));
  }

  Future<void> goTo(String path) async {
    directory = path;
    await scan();
  }

  /// The mounted drives with a root directory, on Windows. Linux would have to
  /// read `/proc/self/mountinfo` and drop the pseudo filesystems; not yet.
  /// [drives] through this browser's own lister.
  Future<List<String>> listDrives() =>
      drives(lister: lister, env: Env(const {}, isWindows: isWindows));

  static Future<List<String>> drives({
    DirectoryLister lister = const SystemDirectoryLister(),
    Env? env,
  }) async {
    if (!(env ?? Env.system()).isWindows) return const [];
    final found = <String>[];
    for (var letter = 'A'.codeUnitAt(0); letter <= 'Z'.codeUnitAt(0); letter++) {
      final root = '${String.fromCharCode(letter)}:/';
      if (await lister.exists(root)) found.add(root);
    }
    return found;
  }

  Future<void> scan() => _start(empty: false);

  /// Rescan the current directory; a request while a walk of the same
  /// directory runs joins that walk.
  Future<void> rescan() => _start(empty: true);

  /// The walk that is running, for [idle]; callers may start a scan without
  /// awaiting it, and tests or `dispose` still have a handle on it.
  Future<void>? _running;
  bool _disposed = false;

  /// A request for the directory a walk is already on joins that walk, so the
  /// handle stays the running one. A request for another directory (`up`,
  /// `goTo`, a drive) cancels the old walk and starts a new one at once.
  Future<void> _start({required bool empty, bool force = false}) {
    final running = _running;
    if (!force && scanning && running != null && _walking == directory) return running;
    final generation = ++_generation;
    final walk = UiTiming.instance.time('browse.scan', () => _scan(empty: empty, generation: generation));
    // A cancelled walk ends at its next step; [idle] still waits for it.
    return _running = running == null ? walk : Future.wait([running, walk]).then((_) {});
  }

  /// Completes when no scan is running any more.
  Future<void> idle() async {
    while (_running != null) {
      final running = _running!;
      await running;
      if (identical(_running, running)) _running = null;
    }
  }

  /// A running walk stops at its next directory and redraws nothing.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _scan({required bool empty, required int generation}) async {
    // A newer walk owns `scanning` and the list from the moment it starts;
    // this one just stops.
    bool cancelled() => _disposed || generation != _generation;
    if (cancelled()) return;
    final root = directory;
    _walking = root;
    scanning = true;
    if (empty) repos = const [];
    error = null;
    notifyListeners();

    final clock = Stopwatch()..start();
    final found = <String>[];
    final samples = <ScanSample>[];
    var visited = 0;
    var skipped = 0;
    var appDataTrees = 0;
    var stopped = false;
    Stopwatch? sincePublish;

    final queue = Queue<_Node>()..add(_Node(root, 0, maxDepth));
    while (queue.isNotEmpty) {
      if (cancelled()) return;
      final node = queue.removeFirst();
      if (++visited > maxDirectories) {
        stopped = true;
        break;
      }

      // One stat, before any listing: a folder that holds a `.git` is a hit, and
      // its own tree is not walked. Listing a directory is the expensive call.
      if (await _hasGit(node.path)) {
        if (cancelled()) return;
        found.add(node.path);
        // Show what is found while the walk goes on: the first hit at once,
        // then at most every [publishEvery].
        if (sincePublish == null || sincePublish.elapsed >= publishEvery) {
          _publish(found);
          sincePublish = Stopwatch()..start();
        }
        // The browsed directory is the one exception: it is usually a repository
        // itself, and the checkouts to switch to live inside it.
        if (node.path != root) continue;
      }
      if (node.depth >= node.limit) continue;

      final listing = Stopwatch()..start();
      List<DirEntry> children;
      try {
        children = await lister.list(node.path);
      } on FileSystemException {
        continue;
      }
      if (cancelled()) return;
      listing.stop();
      samples.add(ScanSample(path: node.path, took: listing.elapsed, entries: children.length));

      for (final child in children) {
        if (!child.isDirectory || child.isLink) continue;
        final clean = _clean(child.path);
        final name = _paths.basename(clean);
        if (skip.contains(name.toLowerCase())) continue;
        // Never below a `.git`, whatever its casing: objects, refs and the rest
        // are nobody's checkout and are expensive to enumerate.
        if (_belowGitDir(clean)) {
          skipped++;
          continue;
        }
        if (_inSkippedTree(clean)) {
          skipped++;
          continue;
        }
        final childDepth = node.depth + 1;
        // AppData is walked, but only two levels in: the per-application cache
        // trees below that are the expensive part and hold no checkouts.
        final isAppData = name.toLowerCase() == 'appdata';
        if (isAppData) appDataTrees++;
        final childLimit = isAppData
            ? (childDepth + appDataDepth < node.limit ? childDepth + appDataDepth : node.limit)
            : node.limit;
        queue.add(_Node(clean, childDepth, childLimit));
      }
      // Let the UI breathe every few directories: on Windows a listing can block
      // the event loop for a moment.
      if (visited % 8 == 0) await Future<void>.delayed(Duration.zero);
    }

    clock.stop();
    if (cancelled()) return;
    found.sort(_byColumns);
    repos = found;
    if (stopped) {
      error = 'stopped after $maxDirectories directories; narrow the folder to see more';
    }
    scanning = false;
    notifyListeners();

    final slowest = [...samples]..sort((a, b) => b.took.compareTo(a.took));
    final widest = [...samples]..sort((a, b) => b.entries.compareTo(a.entries));
    onReport?.call(ScanReport(
      directory: root,
      depth: maxDepth,
      visited: visited,
      found: found.length,
      skipped: skipped,
      elapsed: clock.elapsed,
      slowest: slowest.take(6).toList(),
      widest: widest.take(6).toList(),
      stopped: stopped,
      appDataTrees: appDataTrees,
    ));
  }

  /// The repositories found so far, sorted, on screen while the walk goes on.
  void _publish(List<String> found) {
    repos = [...found]..sort(_byColumns);
    notifyListeners();
  }

  /// A `.git` of its own: a folder for a clone, a file for a worktree or a
  /// submodule. One `type` call, no listing.
  Future<bool> _hasGit(String path) => lister.exists(_paths.join(path, '.git'));

  /// The list's two columns decide the order: the containing path first, then the
  /// base name, both case-insensitive - the order a reader scans the screen.
  static int _byColumns(String a, String b) {
    final left = _split(a);
    final right = _split(b);
    final byFolder = left.$1.toLowerCase().compareTo(right.$1.toLowerCase());
    if (byFolder != 0) return byFolder;
    return left.$2.toLowerCase().compareTo(right.$2.toLowerCase());
  }

  /// The containing path and the base name, split by the host's own rules.
  static (String, String) _split(String path) {
    final clean = _clean(path);
    return (_paths.dirname(clean), _paths.basename(clean));
  }
}

class _Node {
  const _Node(this.path, this.depth, this.limit);

  final String path;
  final int depth;

  /// How deep the walk may go on this branch: [RepoBrowser.maxDepth] normally,
  /// lower inside an `AppData` tree.
  final int limit;
}
