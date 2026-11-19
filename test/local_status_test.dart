import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/status.dart';

/// Records are NUL-terminated: "XY path" then, for a rename, the old path.
String z(List<String> records) => records.map((r) => '$r\u0000').join();

void main() {
  group('parseStatusZ', () {
    test('empty output has no rows', () {
      expect(parseStatusZ(''), isEmpty);
    });

    test('a staged change is one row in Staged', () {
      final rows = parseStatusZ(z(['M  lib/a.dart']));
      expect(rows, hasLength(1));
      expect(rows.single.section, Section.staged);
      expect(rows.single.kind, RowKind.modified);
      expect(rows.single.path, 'lib/a.dart');
      expect(rows.single.isStaged, isTrue);
    });

    test('a worktree change is one row in Changed', () {
      final rows = parseStatusZ(z([' M lib/a.dart']));
      expect(rows.single.section, Section.changed);
      expect(rows.single.code, ' M');
    });

    test('staged and changed make two rows for one path', () {
      final rows = parseStatusZ(z(['MM lib/a.dart']));
      expect(rows.map((r) => r.section), [Section.staged, Section.changed]);
      expect(rows.map((r) => r.path).toSet(), {'lib/a.dart'});
    });

    test('untracked lands in its own section', () {
      final rows = parseStatusZ(z(['?? notes.md']));
      expect(rows.single.section, Section.untracked);
      expect(rows.single.kind, RowKind.untracked);
    });

    test('ignored entries are dropped', () {
      expect(parseStatusZ(z(['!! build/'])), isEmpty);
    });

    test('a rename takes the old path from the next token', () {
      final rows = parseStatusZ(z(['R  new/name.dart', 'old/name.dart']));
      expect(rows.single.kind, RowKind.renamed);
      expect(rows.single.path, 'new/name.dart');
      expect(rows.single.origPath, 'old/name.dart');
    });

    test('every conflict code goes to Conflicts, once', () {
      const codes = ['DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'];
      final rows = parseStatusZ(z([for (final c in codes) '$c merge.txt']));
      expect(rows, hasLength(codes.length));
      expect(rows.every((r) => r.section == Section.conflicts), isTrue);
      expect(rows.every((r) => r.isConflict), isTrue);
    });

    test('a deleted file keeps its kind per side', () {
      expect(parseStatusZ(z([' D gone.txt'])).single.kind, RowKind.deleted);
      expect(parseStatusZ(z(['D  gone.txt'])).single.kind, RowKind.deleted);
    });

    test('paths with spaces survive whole', () {
      final rows = parseStatusZ(z(['?? a file with spaces.txt']));
      expect(rows.single.path, 'a file with spaces.txt');
      expect(rows.single.name, 'a file with spaces.txt');
    });

    test('a folder row keeps its trailing slash in name and folder', () {
      final rows = parseStatusZ(z(['?? build/']));
      expect(rows.single.name, 'build/');
      expect(rows.single.path, 'build/');
    });

    test('name and folder split on the last slash', () {
      final rows = parseStatusZ(z(['M  lib/state/repo.dart']));
      expect(rows.single.name, 'repo.dart');
      expect(rows.single.folder, 'lib/state');
    });

    test('a malformed short record is skipped, the rest parse', () {
      final rows = parseStatusZ(z(['M ', 'M  ok.dart']));
      expect(rows.single.path, 'ok.dart');
    });
  });
}
