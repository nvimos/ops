import 'dart:async';

import '../rpc/client.dart';
import '../timing/ui_timing.dart';
import 'models.dart';
import 'repo_backend.dart';

/// The backend plugin, relay (`~/es/nvimos-poc-backend`), over one RPC connection. It is both the
/// [RepoBackend] and the [EditorSession]: the editor is the Neovim the plugin runs in.
class NvimBackend implements RepoBackend, EditorSession {
  NvimBackend._(this.rpc, this.chan) {
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

  /// Connect and check the plugin; fails after [timeout] when the peer accepts but never answers
  /// (a hung Neovim, or another program on the port). The socket is closed on every failure.
  static Future<NvimBackend> connect(String host, int port, {Duration timeout = const Duration(seconds: 8)}) async {
    final rpc = await NvimRpc.connect(host, port, timeout: timeout);
    try {
      return await _handshake(rpc).timeout(timeout);
    } on NvimError catch (e) {
      await rpc.close();
      if (e.message.contains("module 'nvimos' not found")) {
        throw NvimError('connect', 'the nvimos plugin is not loaded in this Neovim');
      }
      rethrow;
    } catch (_) {
      await rpc.close();
      rethrow;
    }
  }

  static Future<NvimBackend> _handshake(NvimRpc rpc) async {
    final info = asList(await rpc.request('nvim_get_api_info'));
    final b = NvimBackend._(rpc, intOr(info.first));
    final v = await b._lua('nvimos', 'version');
    if (v != apiVersion) {
      throw NvimError('version', 'backend API v$v, this app speaks v$apiVersion');
    }
    return b;
  }

  /// One RPC stream with its seq and resync; [events] and [cursors] are its two owners' views.
  Stream<NvimEvent> get allEvents => _events.stream;

  @override
  Stream<NvimEvent> get events => _events.stream.where((e) => e.domain == 'git' || e.domain == 'jobs');

  @override
  Stream<Cursor> get cursors => _events.stream
      .where((e) => e.domain == 'windows' && e.reason != 'win_closed')
      .map((e) => Cursor(e.reason == 'snapshot' ? asMap(e.data['current']) : e.data));

  @override
  Future<void> get done => rpc.done;

  /// Every backend call goes through here, so each one is timed as `rpc <module>.<fn>`.
  Future<Object?> _lua(String module, String fn, [List<Object?> args = const []]) =>
      UiTiming.instance.time('rpc $module.$fn', () => rpc.lua("return require('$module').$fn(...)", args));

  /// Subscribe; returns each domain's snapshot. Events after it arrive on [events] / [cursors].
  Future<Map<String, Map<String, Object?>>> attach(List<String> domains) async {
    final r = asMap(
      await _lua('nvimos', 'attach', [
        {'chan': chan, 'domains': domains},
      ]),
    );
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

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _events.close();
    await rpc.close();
  }

  // Editor ------------------------------------------------------------------------------------

  @override
  Future<List<String>> getText(int buf) async =>
      asList(asMap(await _lua('nvimos', 'get_text', [buf]))['lines']).map(str).toList();

  @override
  Future<void> open(String path, int line) => _lua('nvimos', 'open', [path, line, 0]);

  @override
  Future<void> show(String rev, String path, int line) => _lua('nvimos', 'show', [rev, path, line, 0]);

  // Git ---------------------------------------------------------------------------------------

  Future<Object?> _git(String fn, [List<Object?> args = const []]) => _lua('nvimos.git', fn, args);

  @override
  Future<Branches> branches() async => Branches(asMap(await _git('branches')));
  @override
  Future<List<Commit>> log(String base, String head) async =>
      asList(await _git('log', [base, head])).map((e) => Commit(asMap(e))).toList();
  @override
  Future<Set<String>> merged(String base) async => asList(await _git('merged', [base])).map(str).toSet();
  @override
  Future<PrDiff> diff(String base, String head) async => PrDiff(asMap(await _git('diff', [base, head])));
  @override
  Future<Status> status() async => Status(asMap(await _git('status')));
  @override
  Future<DiffFile?> diffFile(String path, {required bool staged}) async {
    final r = await _git('diff_file', [path, staged]);
    return r is Map ? DiffFile(asMap(r)) : null;
  }

  @override
  Future<void> stage(String path) => _git('stage', [path]);
  @override
  Future<void> unstage(String path) => _git('unstage', [path]);
  @override
  Future<void> discard(String path) => _git('discard', [path]);
  @override
  Future<void> stageHunk(String path, Hunk h) => _git('stage_hunk', [path, h.ref]);
  @override
  Future<void> unstageHunk(String path, Hunk h) => _git('unstage_hunk', [path, h.ref]);
  @override
  Future<void> discardHunk(String path, Hunk h) => _git('discard_hunk', [path, h.ref]);
  @override
  Future<void> checkout(String branch, {CheckoutHow? how}) => _git('checkout', [branch, if (how != null) how.name]);
  @override
  Future<String> merge(String base, String head) async => str(await _git('merge', [base, head]));
  @override
  Future<String> rebase(String base, String head) async => str(await _git('rebase', [base, head]));
  @override
  Future<String> commit(String message) async => str(await _git('commit', [message]));

  @override
  Future<List<String>> mergePreflight(String base, String head) async =>
      asList(await _lua('nvimos.merge', 'preflight', [base, head])).map(str).toList();
  @override
  Future<MergeStart> mergeStart(String base, String head) async =>
      MergeStart(asMap(await _lua('nvimos.merge', 'start', [base, head])));
  @override
  Future<List<String>> mergeUnmerged(String path) async =>
      asList(await _lua('nvimos.merge', 'unmerged', [path])).map(str).toList();
  @override
  Future<List<ConflictHunk>> mergeHunks(String path, String file) async =>
      asList(await _lua('nvimos.merge', 'hunks', [path, file])).map((e) => ConflictHunk(asMap(e))).toList();
  @override
  Future<void> mergePick(String path, String file, int index, String side) =>
      _lua('nvimos.merge', 'pick', [path, file, index + 1, side]);
  @override
  Future<void> mergeAdd(String path, String file) => _lua('nvimos.merge', 'add', [path, file]);
  @override
  Future<String> mergeFinish(String base, String head, String path) async =>
      str(await _lua('nvimos.merge', 'finish', [base, head, path]));
  @override
  Future<void> mergeAbort(String path) => _lua('nvimos.merge', 'abort', [path]);

  // Files (Tasks mode) ------------------------------------------------------------------------

  Future<Object?> _files(String fn, [List<Object?> args = const []]) => _lua('nvimos.files', fn, args);

  @override
  Future<List<FileEntry>> listFiles(List<String> dirs) async =>
      asList(await _files('list', [dirs])).map((e) => FileEntry(asMap(e))).toList();
  @override
  Future<List<FileText>> readFiles(List<String> paths) async =>
      paths.isEmpty ? [] : asList(await _files('read', [paths])).map((e) => FileText(asMap(e))).toList();
  @override
  Future<void> setLines(String path, List<LineEdit> edits) =>
      _files('set_lines', [path, edits.map((e) => e.toMap()).toList()]);
  @override
  Future<void> move(String from, String to) => _files('move', [from, to]);
  @override
  Future<void> create(String path, List<String> lines) => _files('create', [path, lines]);

  // Ignore files --------------------------------------------------------------------------------

  Future<Object?> _ignore(String fn, [List<Object?> args = const []]) =>
      _lua('nvimos.gitignore', fn, args);

  static IgnoreFileRef? _ignoreRef(Object? v) => v is Map ? IgnoreFileRef.fromMap(asMap(v)) : null;

  @override
  Future<IgnoreSnapshot> loadIgnorePanes({IgnoreFileRef? selected}) async {
    final r = asMap(await _ignore('load', [if (selected != null) selected.toMap()]));
    return IgnoreSnapshot(
      files: asList(r['files']).map((e) => IgnoreFileRef.fromMap(asMap(e))).toList(),
      selected: _ignoreRef(r['selected']),
      text: r['text'] is String ? r['text'] as String : null,
    );
  }

  @override
  Future<List<IgnoreFileRef>> untrackedIgnoreFiles() async =>
      asList(await _ignore('untracked')).map((e) => IgnoreFileRef.fromMap(asMap(e))).toList();

  @override
  Future<String> readIgnoreFile(IgnoreFileRef file) async => str(await _ignore('read', [file.toMap()]));

  @override
  Future<List<IgnoreAppend>> appendIgnoreLines(IgnoreFileRef file, List<String> patterns) async =>
      asList(await _ignore('append', [file.toMap(), patterns]))
          .map((e) => str(e) == 'duplicate' ? IgnoreAppend.duplicate : IgnoreAppend.added)
          .toList();

  @override
  Future<bool> replaceIgnoreLine(
    IgnoreFileRef file,
    int number,
    String expected,
    String? replacement,
  ) async => await _ignore('replace', [file.toMap(), number, expected, replacement]) == true;

  @override
  Future<void> insertIgnoreLine(IgnoreFileRef file, int number, String text) async =>
      _ignore('insert', [file.toMap(), number, text]);

  @override
  Future<void> createIgnoreFile(IgnoreFileRef file) async => _ignore('create', [file.toMap()]);

  // Jobs ---------------------------------------------------------------------------------------

  @override
  Future<int> startJob(String cmd, List<String> args, {String? stdin, String? label}) async => intOr(
    await _lua('nvimos.jobs', 'start', [
      cmd,
      args,
      {'stdin': ?stdin, 'label': ?label},
    ]),
  );

  @override
  Future<void> cancelJob(int id) => _lua('nvimos.jobs', 'cancel', [id]);

  @override
  Future<CliResult> cli(String cmd, List<String> args) async => CliResult(asMap(await _files('cli', [cmd, args])));

  // Directories --------------------------------------------------------------------------------

  @override
  Future<StartDirs> dirs() async => StartDirs(asMap(await _lua('nvimos.dirs', 'list')));

  /// `:cd` there; returns the new cwd.
  @override
  Future<String> cd(String path) async => str(await _lua('nvimos.dirs', 'set', [path]));

  @override
  Future<Tracking> tracking() async => Tracking(asMap(await _lua('nvimos.tracking', 'info')));

  @override
  Future<String?> pluginRoot() async {
    final r = await _lua('nvimos.dirs', 'plugin_root');
    return r is String ? r : null;
  }
}
