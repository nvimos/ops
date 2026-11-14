import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/timing/ui_timing.dart';
import 'support/temp_dirs.dart';

void main() {
  test('stats: count, p50, p95, max in ms', () {
    final s = UiTiming.stats([for (var i = 1; i <= 100; i++) i.toDouble()]);
    expect(s, {'n': 100, 'p50': 51, 'p95': 95, 'max': 100});
  });

  test('spans record the whole action and its phases', () {
    final t = UiTiming(enabled: true);
    final span = t.span('tasks.edit');
    span.mark('optimistic');
    span.end();
    expect(t.samples.keys, unorderedEquals(['tasks.edit', 'tasks.edit/optimistic']));
    expect(t.sync('x', () => 7), 7);
    expect(t.samples['x']!.length, 1);
  });

  test('save keeps one entry per session, the last 30, and totals', () async {
    final dir = keepForCleanup(await Directory.systemTemp.createTemp('ui_timing_'));
    final f = File('${dir.path}/sub/ui-timing.json');
    for (var i = 0; i < 32; i++) {
      final t = UiTiming(enabled: true, file: f, started: DateTime(2026, 1, 1, 0, i));
      t.record('click', Duration(milliseconds: i));
      await t.save();
      await t.save(closing: true); // same session again: replaced, not added
    }
    final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final sessions = data['sessions'] as List;
    expect(sessions.length, 30);
    expect(sessions.last['ended'], isNotNull);
    expect(sessions.first['actions']['click']['max'], 2);
    expect(data['totals']['click'], {'n': 30, 'p95': 31, 'max': 31});
    await dir.delete(recursive: true);
  });

  test('off: records nothing, writes nothing', () async {
    final dir = keepForCleanup(await Directory.systemTemp.createTemp('ui_timing_'));
    final f = File('${dir.path}/ui-timing.json');
    final t = UiTiming(enabled: false, file: f);
    t.record('click', const Duration(milliseconds: 5));
    t.span('a')
      ..mark('b')
      ..end();
    await t.save(closing: true);
    expect(t.samples, isEmpty);
    expect(f.existsSync(), isFalse);
    await dir.delete(recursive: true);
  });
}
