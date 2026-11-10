import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import 'session.dart';

/// State of the Pull request view: two branches, their commits and the base...head diff.
class PrState extends ChangeNotifier {
  PrState(this.session) {
    session.gitChanged.addListener(refresh);
    refresh();
  }

  final Session session;
  Branches? branches;
  String? base, head;
  List<Commit> commits = [];
  PrDiff? diff;
  String? selected; // path of the selected file
  bool loading = false;
  String? error;
  int _gen = 0;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  DiffFile? get selectedFile => diff?.files.where((f) => f.path == selected).firstOrNull;

  /// Reload branches, then commits and diff for the picked pair (keeps the selection).
  Future<void> refresh() async {
    final b = session.backend;
    if (b == null) return;
    final gen = ++_gen;
    loading = true;
    notifyListeners();
    try {
      final br = await b.branches();
      if (gen != _gen) return;
      branches = br;
      final names = br.list.map((x) => x.name).toList();
      if (base == null || !names.contains(base)) {
        base = names.contains('main') ? 'main' : (names.contains('master') ? 'master' : br.current);
      }
      if (head == null || !names.contains(head)) {
        final others = br.list.where((x) => x.name != base).toList()..sort((a, b) => b.date.compareTo(a.date));
        head = others.isNotEmpty ? others.first.name : base;
      }
      if (base != null && head != null && base != head) {
        final results = await Future.wait([b.log(base!, head!), b.diff(base!, head!)]);
        if (gen != _gen) return;
        commits = results[0] as List<Commit>;
        diff = results[1] as PrDiff;
      } else {
        commits = [];
        diff = null;
      }
      if (selected == null || selectedFile == null) {
        selected = diff?.files.firstOrNull?.path;
      }
      error = null;
    } catch (e) {
      if (gen != _gen) return;
      error = '$e';
    } finally {
      if (gen == _gen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void pick({String? base, String? head}) {
    if (base != null) this.base = base;
    if (head != null) this.head = head;
    selected = null;
    refresh();
  }

  void swap() => pick(base: head, head: base);

  void select(String path) {
    selected = path;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    session.gitChanged.removeListener(refresh);
    super.dispose();
  }
}
