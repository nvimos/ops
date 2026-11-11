import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

/// UI timing instrumentation: how long user actions take, from the click to the screen and to
/// the backend's answer, recorded per session and summarized into a state file
/// (`%APPDATA%/nvimos/ui-timing.json`) when the app quits, and every minute in between.
///
/// On in debug and profile builds, off in release; `NVIMOS_TIMING=1` / `0` overrides. When off,
/// every call is a cheap no-op. Hooks sit where all clicks already pass (the backend wrapper, the
/// state actions, Flutter's global pointer route), so no click handler knows about it.
class UiTiming {
  UiTiming({required this.enabled, this.file, DateTime? started}) : started = started ?? DateTime.now();

  static final instance = UiTiming(enabled: _enabledByDefault(), file: _defaultFile());

  static bool _enabledByDefault() {
    final env = Platform.environment['NVIMOS_TIMING'];
    if (env == '1') return true;
    if (env == '0') return false;
    return !kReleaseMode;
  }

  static File? _defaultFile() {
    final base = Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
    return base == null ? null : File('$base/nvimos/ui-timing.json');
  }

  final bool enabled;
  final File? file;
  final DateTime started;
  final _samples = <String, List<double>>{};
  Timer? _flush;

  /// Durations in ms recorded this session, by name.
  Map<String, List<double>> get samples => _samples;

  void record(String name, Duration d) {
    if (!enabled) return;
    _samples.putIfAbsent(name, () => []).add(d.inMicroseconds / 1000);
  }

  /// Start timing an action; mark its phases, end it.
  Span span(String name) => enabled ? Span._(this, name) : Span._off;

  T sync<T>(String name, T Function() f) {
    if (!enabled) return f();
    final sw = Stopwatch()..start();
    try {
      return f();
    } finally {
      record(name, sw.elapsed);
    }
  }

  Future<T> time<T>(String name, Future<T> Function() f) async {
    if (!enabled) return f();
    final sw = Stopwatch()..start();
    try {
      return await f();
    } finally {
      record(name, sw.elapsed);
    }
  }

  // App wiring -----------------------------------------------------------------------------------

  /// Start the session: every pointer down is timed to the end of the next frame
  /// (`input.click→frame`), and the summary is flushed every minute.
  void start() {
    if (!enabled) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _flush = Timer.periodic(const Duration(minutes: 1), (_) => save());
  }

  void _onPointer(PointerEvent e) {
    if (e is! PointerDownEvent) return;
    final sw = Stopwatch()..start();
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => record('input.click→frame', sw.elapsed))
      ..scheduleFrame();
  }

  /// Write this session's summary into the state file: the last 30 sessions, and running totals.
  Future<void> save({bool closing = false}) async {
    final f = file;
    if (!enabled || f == null) return;
    if (closing) _flush?.cancel();
    final data = _read(f);
    final sessions = (data['sessions'] as List? ?? []).cast<Map<String, Object?>>()
      ..removeWhere((s) => s['started'] == started.toIso8601String());
    sessions.add(summary(closing: closing));
    data['sessions'] = sessions.length > 30 ? sessions.sublist(sessions.length - 30) : sessions;
    data['totals'] = _totals(sessions);
    try {
      f.parent.createSync(recursive: true);
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } catch (_) {}
  }

  static Map<String, Object?> _read(File f) {
    try {
      return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }

  /// This session: per action, count and p50 / p95 / max in ms.
  Map<String, Object?> summary({bool closing = false}) => {
    'started': started.toIso8601String(),
    'ended': closing ? DateTime.now().toIso8601String() : null,
    'actions': {for (final e in (_samples.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) e.key: stats(e.value)},
  };

  /// Across the kept sessions: per action, total count, the worst p95 and max.
  static Map<String, Object?> _totals(List<Map<String, Object?>> sessions) {
    final out = <String, Map<String, num>>{};
    for (final s in sessions) {
      for (final MapEntry(:key, :value) in (s['actions'] as Map? ?? {}).cast<String, Map>().entries) {
        final t = out.putIfAbsent(key, () => {'n': 0, 'p95': 0, 'max': 0});
        t['n'] = t['n']! + (value['n'] as num);
        t['p95'] = math.max(t['p95']!, value['p95'] as num);
        t['max'] = math.max(t['max']!, value['max'] as num);
      }
    }
    return out;
  }

  static Map<String, num> stats(List<double> ms) {
    final s = [...ms]..sort();
    double at(double q) => s[((s.length - 1) * q).round()];
    double r(double v) => (v * 10).round() / 10;
    return {'n': s.length, 'p50': r(at(.5)), 'p95': r(at(.95)), 'max': r(s.last)};
  }
}

/// One timed action. Phases are recorded as `name/phase`, the whole as `name`.
class Span {
  Span._(this._t, this.name) : _sw = Stopwatch()..start();

  static final _off = Span._(UiTiming(enabled: false), '');

  final UiTiming _t;
  final String name;
  final Stopwatch _sw;

  void mark(String phase) => _t.record('$name/$phase', _sw.elapsed);

  /// Mark [phase] when the next frame is on screen (what the user sees after the click).
  void markPainted([String phase = 'paint']) {
    if (!_t.enabled) return;
    try {
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => mark(phase))
        ..scheduleFrame();
    } catch (_) {
      // No binding (plain unit tests): nothing is painted.
    }
  }

  void end() => _t.record(name, _sw.elapsed);
}
