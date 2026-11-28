import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/main.dart' show showPrefsRecovery;
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';

import 'support/temp_dirs.dart';

void main() {
  late Directory base;

  setUp(() {
    base = keepForCleanup(Directory.systemTemp.createTempSync('nvimos_prefs_'));
    addTearDown(() => Prefs.baseOverride = null);
    Prefs.baseOverride = base.path;
  });

  test('a truncated state file is kept aside and a later save does not touch it', () {
    final bytes = <int>[...utf8.encode('{"lastSeen":{"webshop":1},"flags":{"wrap":'), 0xFF];
    final file = _stateFile(base);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);

    final prefs = Prefs.load();
    final kept = _asides(base);
    expect(kept, hasLength(1));
    expect(_name(kept.single), matches(RegExp(r'^state\.json\.bad-\d{4}-\d{2}-\d{2}-\d{6}$')));
    expect(prefs.recoveryNotice, 'Settings file could not be read. The old file was kept at ${kept.single.path}');
    expect(kept.single.readAsBytesSync(), bytes);
    expect(file.existsSync(), isFalse);

    // TasksView loads again after startup has moved the file: a missing file, not a second recovery.
    final again = Prefs.load();
    expect(again.recoveryNotice, isNull);
    expect(_asides(base), hasLength(1));

    prefs.setFlag('wrap', true);

    expect(kept.single.readAsBytesSync(), bytes);
    expect(_asides(base), hasLength(1));
    final saved = jsonDecode(file.readAsStringSync()) as Map;
    expect(saved['flags'], {'wrap': true});
    expect(saved.containsKey('lastSeen'), isFalse);
  });

  test('a missing file is a fresh start: save creates it, nothing is renamed, no notice', () {
    final prefs = Prefs.load();
    expect(prefs.recoveryNotice, isNull);
    expect(_stateFile(base).existsSync(), isFalse);

    prefs.setFlag('wrap', false);

    expect(prefs.recoveryNotice, isNull);
    expect(_asides(base), isEmpty);
    expect(jsonDecode(_stateFile(base).readAsStringSync()), {'flags': {'wrap': false}});
  });

  test('a JSON list is broken settings, not an empty file to overwrite', () {
    const original = '["not","settings"]';
    final file = _stateFile(base);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(original);

    final prefs = Prefs.load();
    final kept = _asides(base);
    expect(kept, hasLength(1));
    expect(file.existsSync(), isFalse);
    expect(kept.single.readAsStringSync(), original);
    expect(prefs.recoveryNotice, 'Settings file could not be read. The old file was kept at ${kept.single.path}');

    prefs.setFlag('wrap', true);

    expect(kept.single.readAsBytesSync(), utf8.encode(original));
    expect(jsonDecode(file.readAsStringSync()), {'flags': {'wrap': true}});
  });

  test('a valid object, including an empty one, is not renamed', () {
    final file = _stateFile(base);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{}');

    var prefs = Prefs.load();
    expect(prefs.recoveryNotice, isNull);
    expect(_asides(base), isEmpty);
    expect(file.readAsStringSync(), '{}');

    file.writeAsStringSync('{"lastSeen":{"webshop":1}}');
    prefs = Prefs.load();
    expect(prefs.recoveryNotice, isNull);
    expect(prefs.lastSeen('webshop'), DateTime.fromMillisecondsSinceEpoch(1));
    expect(_asides(base), isEmpty);
    expect(file.readAsStringSync(), '{"lastSeen":{"webshop":1}}');
  });

  test('startup shows the aside path through the notice bar', () {
    final file = _stateFile(base);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"flags":');

    final session = Session(prefs: Prefs.load());
    addTearDown(session.dispose);
    showPrefsRecovery(session);

    final notice = session.notices.current;
    expect(notice?.failure, isTrue);
    expect(notice?.message, contains(_asides(base).single.path));
  });

  test('an aside name that is already taken is not overwritten', () {
    final dir = Directory('${base.path}/nvimos')..createSync(recursive: true);
    final start = DateTime.now();
    for (var i = 0; i < 3; i++) {
      File('${dir.path}/${_badStamp(start.add(Duration(seconds: i)))}').writeAsStringSync('occupied');
    }
    final file = _stateFile(base)..writeAsStringSync('[1]');

    final prefs = Prefs.load();
    final kept = _asides(base);
    expect(kept, hasLength(4));
    final moved = kept.where((f) => f.readAsStringSync() == '[1]').single;
    expect(_name(moved), matches(RegExp(r'^state\.json\.bad-\d{4}-\d{2}-\d{2}-\d{6}-\d+$')));
    expect(prefs.recoveryNotice, contains(moved.path));
    for (final f in kept.where((f) => f.path != moved.path)) {
      expect(f.readAsStringSync(), 'occupied');
    }
    expect(file.existsSync(), isFalse);
  });
}

File _stateFile(Directory base) => File('${base.path}/nvimos/state.json');

List<File> _asides(Directory base) {
  final dir = Directory('${base.path}/nvimos');
  if (!dir.existsSync()) return const [];
  return [
    for (final e in dir.listSync())
      if (e is File && _name(e).startsWith('state.json.bad-')) e,
  ];
}

String _name(FileSystemEntity e) => e.path.split(RegExp(r'[/\\]')).last;

String _badStamp(DateTime t) {
  String p(int n, int w) => n.toString().padLeft(w, '0');
  final stamp = '${p(t.year, 4)}-${p(t.month, 2)}-${p(t.day, 2)}-${p(t.hour, 2)}${p(t.minute, 2)}${p(t.second, 2)}';
  return 'state.json.bad-$stamp';
}
