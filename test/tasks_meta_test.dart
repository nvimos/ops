import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/tasks/parse.dart';

/// Parses the real planning repo next to this one (skipped when it isn't there).
void main() {
  final root = Directory('${Directory.current.parent.path}/nvimos-meta');
  final skip = root.existsSync() ? null : 'nvimos-meta not found';

  List<String> read(File f) => f.readAsLinesSync();
  String rel(FileSystemEntity f) => f.path.replaceAll('\\', '/').substring(root.path.replaceAll('\\', '/').length + 1);

  test('every Backlog.md task parses with an id, title and known status', () {
    final files = Directory('${root.path}/backlog')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('task-'));
    final (statuses, _) = parseBacklogConfig(read(File('${root.path}/backlog/config.yml')));
    var n = 0;
    for (final f in files) {
      final t = parseTask(rel(f), read(f));
      expect(t.id, startsWith('TASK-'), reason: f.path);
      expect(t.title, isNotEmpty, reason: f.path);
      expect(statuses, contains(t.status), reason: f.path);
      n++;
    }
    expect(n, greaterThan(50));
  }, skip: skip);

  test('every OpenSpec change parses and names its task', () {
    final files = <String, List<String>>{};
    for (final f in Directory('${root.path}/openspec/changes').listSync(recursive: true).whereType<File>()) {
      files[rel(f)] = read(f);
    }
    final changes = parseChanges(files, {});
    // OpenSpec holds only the changes that need a design (2026-11-11); the rest is Backlog.md.
    expect(changes.length, greaterThan(3));
    for (final c in changes) {
      expect(c.taskId, startsWith('TASK-'), reason: c.dir);
      expect(c.checkGroups, isNotEmpty, reason: c.dir);
    }
    expect(changes.where((c) => c.archived), isNotEmpty);
    expect(changes.where((c) => c.deltas.isNotEmpty), isNotEmpty);
  }, skip: skip);

  test('legacy notes yield items, some marked untested', () {
    final items = [
      for (final f in Directory(
        '${root.path}/legacy',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.md')))
        ...parseLegacy(rel(f).substring(7), read(f)),
    ];
    expect(items.length, greaterThan(50));
    expect(items.where((i) => i.untested), isNotEmpty);
  }, skip: skip);
}
