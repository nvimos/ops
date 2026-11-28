import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// The host side of `make snappy-app`: receives the frame timings of
/// `integration_test/snappy_app_test.dart`, records the run and compares it with the baseline.
///
/// Records (`out/` is git-ignored):
/// - `out/snappy-app/<yyyy-mm-dd-HHMM>.json`: the whole run, the engine's summary per key
/// - `out/snappy-app/history.tsv`: one line per key and run (date, commit, key, p90 build, p90
///   raster, missed frames), the trend over runs
///
/// Checks, per `<view>/<interaction>` key, on the p90 frame build and raster times:
/// - over [budget] (one 60 Hz frame) fails
/// - over [drift] times the baseline (`test/fixtures/snappy_app_baseline.json`, the slowest of a
///   few runs) and above the noise floor is drift: printed, and failing with `SNAPPY_STRICT=1`
///   (`make snappy-app strict=1`)
/// - keys without a baseline are listed
Future<void> main() => integrationDriver(responseDataCallback: record);

const budget = 16.7;
const drift = 1.5;

/// Times this small are noise; drift is only judged above them. Raster (the GPU) is the noisier
/// one: two runs with no code change differed up to 2x on an 11-frame click (6.5 vs 13.8 ms), while
/// build (the framework, our code) stayed within about 0.3 ms; half a frame is the raster floor.
const buildFloor = 4.0, rasterFloor = 8.0;

Future<void> record(Map<String, dynamic>? data) async {
  if (data == null || data.isEmpty) {
    stderr.writeln('snappy-app: no frame timings came back');
    exit(1);
  }
  final now = DateTime.now();
  final stamp = '${now.year}-${_two(now.month)}-${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';
  final commit = _commit();
  final keys = <String, Map<String, num>>{
    for (final MapEntry(:key, :value) in data.entries)
      if (value is Map) key: _pick(value.cast<String, dynamic>()),
  };

  final dir = Directory('out/snappy-app')..createSync(recursive: true);
  File('${dir.path}/$stamp.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({'date': now.toIso8601String(), 'commit': commit, 'keys': keys, 'raw': data}),
  );
  final history = File('${dir.path}/history.tsv');
  if (!history.existsSync()) history.writeAsStringSync('date\tcommit\tkey\tp90_build\tp90_raster\tmissed\n');
  history.writeAsStringSync(
    [
      for (final MapEntry(:key, :value) in keys.entries)
        '$stamp\t$commit\t$key\t${value['p90_build']}\t${value['p90_raster']}\t${value['missed']}\n',
    ].join(),
    mode: FileMode.append,
  );

  final base = _baseline();
  final strict = Platform.environment['SNAPPY_STRICT'] == '1';
  final width = keys.keys.fold(0, (w, k) => k.length > w ? k.length : w);
  var failed = false;
  for (final MapEntry(:key, :value) in keys.entries) {
    final b = value['p90_build']!.toDouble(), r = value['p90_raster']!.toDouble();
    final was = base[key];
    final verdict = switch (()) {
      _ when b > budget || r > budget => 'over',
      _ when was == null => 'new',
      _ when _drifted(b, was['p90_build'], buildFloor) || _drifted(r, was['p90_raster'], rasterFloor) => 'drift',
      _ => 'ok',
    };
    if (verdict == 'over' || (verdict == 'drift' && strict)) failed = true;
    final then = was == null ? '' : '  was ${_ms(was['p90_build'])} ${_ms(was['p90_raster'])}';
    stdout.writeln('${verdict.padLeft(5)} ${key.padRight(width)}  build ${_ms(b)}  raster ${_ms(r)}  '
        'frames ${'${value['frames']}'.padLeft(3)}  missed ${value['missed']}$then');
  }
  for (final k in base.keys.where((k) => !keys.containsKey(k))) {
    stdout.writeln('gone ${k.padRight(width)}  in the baseline, not measured');
  }
  stdout.writeln('recorded out/snappy-app/$stamp.json');
  if (failed) exit(1);
}

bool _drifted(double now, num? was, double floor) => was != null && now > floor && now > was * drift;

/// What the checks and the history use, out of the engine's frame summary (milliseconds).
Map<String, num> _pick(Map<String, dynamic> s) => {
  'frames': s['frame_count'] as num? ?? 0,
  'avg_build': s['average_frame_build_time_millis'] as num? ?? 0,
  'p90_build': s['90th_percentile_frame_build_time_millis'] as num? ?? 0,
  'p99_build': s['99th_percentile_frame_build_time_millis'] as num? ?? 0,
  'worst_build': s['worst_frame_build_time_millis'] as num? ?? 0,
  'avg_raster': s['average_frame_rasterizer_time_millis'] as num? ?? 0,
  'p90_raster': s['90th_percentile_frame_rasterizer_time_millis'] as num? ?? 0,
  'p99_raster': s['99th_percentile_frame_rasterizer_time_millis'] as num? ?? 0,
  'missed':
      (s['missed_frame_build_budget_count'] as num? ?? 0) + (s['missed_frame_rasterizer_budget_count'] as num? ?? 0),
};

Map<String, Map<String, dynamic>> _baseline() {
  final f = File('test/fixtures/snappy_app_baseline.json');
  if (!f.existsSync()) return {};
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return (j['keys'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()));
}

String _commit() {
  final r = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
  final dirty = Process.runSync('git', ['status', '--porcelain', '--untracked-files=no']).stdout.toString().trim();
  return '${r.stdout.toString().trim()}${dirty.isEmpty ? '' : '+'}';
}

String _two(int n) => '$n'.padLeft(2, '0');

String _ms(num? v) => v == null ? '   -' : v.toStringAsFixed(1).padLeft(5);
