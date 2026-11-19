import 'package:flutter/foundation.dart';

import '../local/browser.dart';
import 'action_queue.dart';
import 'session.dart';

/// One line in the Log: an action result or a repository scan.
class LogEntry {
  const LogEntry({required this.at, required this.title, required this.detail, this.error = false});

  final DateTime at;
  final String title;
  final String detail;
  final bool error;

  String get time {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}

/// The Log mode's data: the action reports the queue keeps plus the crawler's
/// scans, newest first. It never queries git or the filesystem itself.
class LogState extends ChangeNotifier {
  LogState(this.session) {
    _seen = session.actions.reports.length;
    session.actions.reportsChanged.addListener(_readReports);
    _readReports();
  }

  final Session session;
  final List<LogEntry> _entries = [];
  int _seen = 0;
  bool _disposed = false;

  List<LogEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  void _readReports() {
    final reports = session.actions.reports;
    for (var i = _seen; i < reports.length; i++) {
      _entries.insert(0, _entry(reports[i]));
    }
    _seen = reports.length;
    _trim();
    notifyListeners();
  }

  static LogEntry _entry(ActionResult result) {
    final failure = result.failure;
    final detail = failure?.detail ??
        [
          'origin: ${result.origin ?? result.name}',
          if (result.command != null) 'command: ${result.command}',
          'changed: ${result.changed}',
        ].join('\n');
    return LogEntry(
      at: DateTime.now(),
      title: failure?.summary ?? '${result.name}: done',
      detail: detail,
      error: !result.ok,
    );
  }

  /// A finished repository scan.
  void addScan(ScanReport report) {
    _entries.insert(0, LogEntry(at: DateTime.now(), title: report.summary, detail: report.detail));
    _trim();
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void _trim() {
    if (_entries.length > 200) _entries.removeRange(200, _entries.length);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    session.actions.reportsChanged.removeListener(_readReports);
    super.dispose();
  }
}
