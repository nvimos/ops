import 'dart:async';

import '../rpc/client.dart';
import 'models.dart';

/// An event from the backend plugin, in seq order per domain. A resync shows up as reason
/// 'snapshot' with the domain's full snapshot in [data].
class NvimEvent {
  NvimEvent(this.domain, this.reason, this.seq, this.data);
  final String domain, reason;
  final int seq;
  final Map<String, Object?> data;

  @override
  String toString() => 'NvimEvent($domain#$seq $reason)';
}

/// The backend plugin (`~/es/nvimos-poc-backend`) over one RPC connection.
class Backend {
  Backend._(this.rpc, this.chan) {
    _sub = rpc.notifications.listen((n) {
      if (n.method == 'nvimos' && n.args.isNotEmpty) handleEvent(asMap(n.args[0]));
    });
  }

  final NvimRpc rpc;
  final int chan;
  late final StreamSubscription<RpcNotification> _sub;
  final _events = StreamController<NvimEvent>.broadcast();
  final _seq = <String, int>{};
  final _resyncing = <String>{};

  static const apiVersion = 1;

  static Future<Backend> connect(String host, int port) async {
    final rpc = await NvimRpc.connect(host, port);
    try {
      final info = asList(await rpc.request('nvim_get_api_info'));
      final b = Backend._(rpc, intOr(info.first));
      final v = await b._lua('nvimos', 'version');
      if (v != apiVersion) {
        throw NvimError('version', 'backend API v$v, this app speaks v$apiVersion');
      }
      return b;
    } on NvimError catch (e) {
      await rpc.close();
      if (e.message.contains("module 'nvimos' not found")) {
        throw NvimError('connect', 'the nvimos plugin is not loaded in this Neovim');
      }
      rethrow;
    }
  }

  Stream<NvimEvent> get events => _events.stream;
  Future<void> get done => rpc.done;

  Future<Object?> _lua(String module, String fn, [List<Object?> args = const []]) =>
      rpc.lua("return require('$module').$fn(...)", args);

  /// Subscribe; returns each domain's snapshot. Events after it arrive on [events].
  Future<Map<String, Map<String, Object?>>> attach(List<String> domains) async {
    final r = asMap(await _lua('nvimos', 'attach', [
      {'chan': chan, 'domains': domains},
    ]));
    final seq = asMap(r['seq']);
    final snaps = asMap(r['snapshot']);
    for (final d in domains) {
      _seq[d] = intOr(seq[d]);
    }
    return {for (final d in domains) d: asMap(snaps[d])};
  }

  /// Order events per domain: drop stale ones, resync on a gap. Public for tests.
  void handleEvent(Map<String, Object?> ev) {
    final domain = str(ev['domain']);
    final seq = intOr(ev['seq']);
    final last = _seq[domain];
    if (last == null || _resyncing.contains(domain) || seq <= last) return;
    if (seq != last + 1) {
      _resync(domain);
      return;
    }
    _seq[domain] = seq;
    _events.add(NvimEvent(domain, str(ev['reason']), seq, ev));
  }

  Future<void> _resync(String domain) async {
    _resyncing.add(domain);
    try {
      final r = asMap(await _lua('nvimos', 'resync', [domain]));
      _seq[domain] = intOr(r['seq']);
      _events.add(NvimEvent(domain, 'snapshot', intOr(r['seq']), asMap(r['snapshot'])));
    } catch (_) {
      // Connection gone; nothing to resync.
    } finally {
      _resyncing.remove(domain);
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    await _events.close();
    await rpc.close();
  }

  // Editor ------------------------------------------------------------------------------------

  Future<List<String>> getText(int buf) async => asList(asMap(await _lua('nvimos', 'get_text', [buf]))['lines']).map(str).toList();

  /// Edit a working-tree file (relative to the repo root) at a 1-based line.
  Future<void> open(String path, int line) => _lua('nvimos', 'open', [path, line, 0]);

  /// Show a file as it is on [rev] in a read-only buffer, at a 1-based line.
  Future<void> show(String rev, String path, int line) => _lua('nvimos', 'show', [rev, path, line, 0]);

  // Git ---------------------------------------------------------------------------------------

  Future<Object?> _git(String fn, [List<Object?> args = const []]) => _lua('nvimos.git', fn, args);

  Future<Branches> branches() async => Branches(asMap(await _git('branches')));
  Future<List<Commit>> log(String base, String head) async =>
      asList(await _git('log', [base, head])).map((e) => Commit(asMap(e))).toList();
  Future<PrDiff> diff(String base, String head) async => PrDiff(asMap(await _git('diff', [base, head])));
  Future<Status> status() async => Status(asMap(await _git('status')));
  Future<DiffFile?> diffFile(String path, {required bool staged}) async {
    final r = await _git('diff_file', [path, staged]);
    return r is Map ? DiffFile(asMap(r)) : null;
  }

  Future<void> stage(String path) => _git('stage', [path]);
  Future<void> unstage(String path) => _git('unstage', [path]);
  Future<void> discard(String path) => _git('discard', [path]);
  Future<void> stageHunk(String path, Hunk h) => _git('stage_hunk', [path, h.ref]);
  Future<void> unstageHunk(String path, Hunk h) => _git('unstage_hunk', [path, h.ref]);
  Future<void> discardHunk(String path, Hunk h) => _git('discard_hunk', [path, h.ref]);
  Future<void> checkout(String branch) => _git('checkout', [branch]);
  Future<String> commit(String message) async => str(await _git('commit', [message]));

  // Files (Tasks mode) ------------------------------------------------------------------------

  Future<Object?> _files(String fn, [List<Object?> args = const []]) => _lua('nvimos.files', fn, args);

  Future<List<FileEntry>> listFiles(List<String> dirs) async =>
      asList(await _files('list', [dirs])).map((e) => FileEntry(asMap(e))).toList();
  Future<List<FileText>> readFiles(List<String> paths) async =>
      paths.isEmpty ? [] : asList(await _files('read', [paths])).map((e) => FileText(asMap(e))).toList();
  Future<void> setLines(String path, List<LineEdit> edits) =>
      _files('set_lines', [path, edits.map((e) => e.toMap()).toList()]);
  Future<void> move(String from, String to) => _files('move', [from, to]);
  Future<void> create(String path, List<String> lines) => _files('create', [path, lines]);
  Future<CliResult> cli(String cmd, List<String> args) async => CliResult(asMap(await _files('cli', [cmd, args])));
}
