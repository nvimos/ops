import 'dart:convert';
import 'dart:io';

/// `make snappy-baseline`: the last `make snappy-app` runs become the baseline the next runs are
/// compared with (`test/fixtures/snappy_app_baseline.json`, checked in): per key the slowest p90 of
/// the newest [runs] runs, so the run-to-run noise (raster time up to 2x on short interactions) is
/// inside the baseline instead of reported as drift. An explicit step: take it after a change made
/// things faster, or on another machine; commit it by hand.
const runs = 3;

void main() {
  final dir = Directory('out/snappy-app');
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  if (files.isEmpty) {
    stderr.writeln('no run in out/snappy-app: make snappy-app first');
    exit(1);
  }
  final used = files.sublist(files.length > runs ? files.length - runs : 0);
  final keys = <String, Map<String, num>>{};
  Map<String, dynamic>? last;
  for (final f in used) {
    final run = last = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    for (final MapEntry(:key, :value) in (run['keys'] as Map<String, dynamic>).entries) {
      final v = (value as Map).cast<String, num>();
      final k = keys.putIfAbsent(key, () => {'p90_build': 0, 'p90_raster': 0});
      for (final m in ['p90_build', 'p90_raster']) {
        if (v[m]! > k[m]!) k[m] = v[m]!;
      }
    }
  }
  final out = File('test/fixtures/snappy_app_baseline.json');
  out.writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert({
      'taken': last!['date'],
      'commit': last['commit'],
      'runs': [for (final f in used) f.uri.pathSegments.last],
      'keys': keys,
    })}\n',
  );
  stdout.writeln('baseline ${out.path}');
  for (final f in used) {
    stdout.writeln('    from ${f.path.replaceAll(r'\', '/')}');
  }
}
