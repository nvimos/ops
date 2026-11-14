import 'dart:io';

import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import 'session.dart';

/// The mode a project opens in: the first one with something to do.
enum OpenTarget { pullRequest, changes, tasks }

/// A branch other than the default one means a pull request to review; else uncommitted changes
/// mean work to stage; else the tasks, even when there are none.
OpenTarget openTarget(Branches branches, Status status) {
  final names = branches.list.map((b) => b.name).toSet();
  final main = names.contains('main') ? 'main' : (names.contains('master') ? 'master' : branches.current);
  if (names.any((n) => n != main)) return OpenTarget.pullRequest;
  if (status.files.isNotEmpty) return OpenTarget.changes;
  return OpenTarget.tasks;
}

/// State of the Directories mode: the start dirs, a filter, and switching the Active Directory,
/// either by `:cd` in the connected Neovim or by starting a new Neovim there.
class DirsState extends ChangeNotifier {
  DirsState(this.session, {this.launch = launchNeovim}) {
    session.addListener(_onSession);
    _onSession();
  }

  final Session session;

  /// Starts a Neovim listening on [address] in [dir] with the backend plugin at [pluginRoot].
  final Future<void> Function(String dir, String address, String pluginRoot) launch;

  StartDirs? dirs;
  String filter = '';
  int cursor = 0;
  bool loading = false;
  String? error;

  /// Picking a dir starts a new Neovim there instead of moving the connected one.
  bool newNeovim = false;

  bool _disposed = false;
  bool _wasConnected = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// The Active Directory: the connected Neovim's cwd.
  String? get active => session.repo?.cwd;

  List<String> get shown {
    final all = dirs?.dirs ?? const [];
    final q = filter.trim().toLowerCase();
    return q.isEmpty ? all : all.where((d) => d.toLowerCase().contains(q)).toList();
  }

  void _onSession() {
    final connected = session.conn == Conn.connected;
    if (connected && !_wasConnected) load();
    _wasConnected = connected;
  }

  Future<void> load() async {
    final b = session.backend;
    if (b == null) return;
    loading = true;
    notifyListeners();
    try {
      dirs = await b.dirs();
      error = null;
    } catch (e) {
      error = '$e';
    }
    loading = false;
    cursor = cursor.clamp(0, (shown.length - 1).clamp(0, 1 << 30));
    notifyListeners();
  }

  void setFilter(String q) {
    filter = q;
    cursor = 0;
    notifyListeners();
  }

  void move(int delta) {
    final n = shown.length;
    if (n == 0) return;
    cursor = (cursor + delta).clamp(0, n - 1);
    notifyListeners();
  }

  void toggleNewNeovim() {
    newNeovim = !newNeovim;
    notifyListeners();
  }

  /// Where the Active Directory opens (see [openTarget]); the tasks when git can't tell.
  Future<OpenTarget> openingTarget() async {
    final b = session.backend;
    if (b == null) return OpenTarget.tasks;
    try {
      return openTarget(await b.branches(), await b.status());
    } catch (_) {
      return OpenTarget.tasks;
    }
  }

  /// Make [dir] the Active Directory. Returns the error text, or null.
  Future<String?> pick(String dir) async {
    if (!newNeovim) {
      String? cwd;
      final err = await session.run((b) async => cwd = await b.cd(dir));
      if (cwd != null && session.repo?.cwd != cwd) session.movedTo(cwd!);
      return err;
    }
    final b = session.backend;
    if (b == null) return 'not connected';
    try {
      final root = await b.pluginRoot();
      if (root == null) return 'cannot find the nvimos plugin to start a new Neovim with';
      final port = await _freePort();
      final address = '127.0.0.1:$port';
      await launch(dir, address, root);
      // Drops the current connection; retries every 2 s until the new Neovim listens.
      await session.connect(address: address);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_onSession);
    super.dispose();
  }
}

/// Start Neovim in a new console window, listening on [address], with the backend plugin added
/// after the user's config (which may reset the runtimepath), like `make nvim`.
Future<void> launchNeovim(String dir, String address, String pluginRoot) async {
  final nvim = ['nvim', '--listen', address, '-c', 'set rtp^=$pluginRoot', '-c', 'runtime plugin/nvimos.lua'];
  if (Platform.isWindows) {
    // `start ""` opens a new console; the empty first argument is the window title.
    await Process.start('cmd', ['/c', 'start', '', ...nvim], workingDirectory: dir, mode: ProcessStartMode.detached);
  } else {
    await Process.start(nvim.first, nvim.sublist(1), workingDirectory: dir, mode: ProcessStartMode.detached);
  }
}
