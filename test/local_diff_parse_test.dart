import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/local/diff_parse.dart';

void main() {
  group('parseDiff', () {
    test('empty text has no files', () {
      expect(parseDiff(''), isEmpty);
    });

    test('a modified file carries paths, counts and line numbers', () {
      final files = parseDiff('''
diff --git a/lib/a.dart b/lib/a.dart
index 1111111..2222222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,3 +1,4 @@
 one
-two
+TWO
 three
+four
''');
      expect(files, hasLength(1));
      final f = files.single;
      expect(f.path, 'lib/a.dart');
      expect(f.oldPath, 'lib/a.dart');
      expect(f.status, 'modified');
      expect(f.binary, isFalse);
      expect(f.additions, 2);
      expect(f.deletions, 1);
      expect(f.hunks, hasLength(1));

      final h = f.hunks.single;
      expect(h.oldStart, 1);
      expect(h.oldCount, 3);
      expect(h.newStart, 1);
      expect(h.newCount, 4);
      expect(h.section, '');
      expect(h.lines.map((l) => l.kind), [
        LineKind.context,
        LineKind.del,
        LineKind.add,
        LineKind.context,
        LineKind.add,
      ]);
      expect(h.lines[0].text, 'one');
      expect((h.lines[0].oldLine, h.lines[0].newLine), (1, 1));
      expect((h.lines[1].oldLine, h.lines[1].newLine), (2, null));
      expect((h.lines[2].oldLine, h.lines[2].newLine), (null, 2));
      expect((h.lines[3].oldLine, h.lines[3].newLine), (3, 3));
      expect((h.lines[4].oldLine, h.lines[4].newLine), (null, 4));
    });

    test('an added file is added, and /dev/null keeps the diff-git paths', () {
      final files = parseDiff('''
diff --git a/new.txt b/new.txt
new file mode 100644
index 0000000..1111111
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,2 @@
+hello
+world
''');
      final f = files.single;
      expect(f.status, 'added');
      expect(f.path, 'new.txt');
      expect(f.additions, 2);
      expect(f.deletions, 0);
      expect(f.hunks.single.newStart, 1);
      expect(f.hunks.single.newCount, 2);
      expect(f.hunks.single.lines.map((l) => l.newLine), [1, 2]);
    });

    test('a deleted file is deleted with a zero new range', () {
      final files = parseDiff('''
diff --git a/old.txt b/old.txt
deleted file mode 100644
index 1111111..0000000
--- a/old.txt
+++ /dev/null
@@ -1,2 +0,0 @@
-bye
-gone
''');
      final f = files.single;
      expect(f.status, 'deleted');
      expect(f.path, 'old.txt');
      expect(f.deletions, 2);
      final h = f.hunks.single;
      expect((h.oldStart, h.oldCount, h.newStart, h.newCount), (1, 2, 0, 0));
      expect(h.lines.map((l) => l.oldLine), [1, 2]);
      expect(h.lines.every((l) => l.newLine == null), isTrue);
    });

    test('a rename takes old_path from rename from and path from rename to', () {
      final files = parseDiff('''
diff --git a/lib/old_name.dart b/lib/new_name.dart
similarity index 90%
rename from lib/old_name.dart
rename to lib/new_name.dart
index 1111111..2222222 100644
--- a/lib/old_name.dart
+++ b/lib/new_name.dart
@@ -1,2 +1,2 @@
 a
-b
+B
''');
      final f = files.single;
      expect(f.status, 'renamed');
      expect(f.oldPath, 'lib/old_name.dart');
      expect(f.path, 'lib/new_name.dart');
      expect(f.additions, 1);
      expect(f.deletions, 1);
    });

    test('a binary diff has no hunks and no counts', () {
      final files = parseDiff('''
diff --git a/logo.png b/logo.png
index 1111111..2222222 100644
Binary files a/logo.png and b/logo.png differ
''');
      final f = files.single;
      expect(f.binary, isTrue);
      expect(f.status, 'modified');
      expect(f.path, 'logo.png');
      expect(f.hunks, isEmpty);
      expect((f.additions, f.deletions), (0, 0));
    });

    test('multiple hunks each keep their own range, section and numbering', () {
      final files = parseDiff('''
diff --git a/multi.txt b/multi.txt
--- a/multi.txt
+++ b/multi.txt
@@ -1,2 +1,2 @@
 alpha
-beta
+beta
@@ -10,2 +10,3 @@ func section()
 ctx
+new
 ctx2
''');
      final f = files.single;
      expect(f.hunks, hasLength(2));
      expect(f.additions, 2);
      expect(f.deletions, 1);

      final first = f.hunks[0];
      expect((first.oldStart, first.oldCount, first.newStart, first.newCount), (1, 2, 1, 2));
      expect(first.section, '');

      final second = f.hunks[1];
      expect(second.header, '@@ -10,2 +10,3 @@ func section()');
      expect((second.oldStart, second.oldCount, second.newStart, second.newCount), (10, 2, 10, 3));
      expect(second.section, 'func section()');
      expect(second.lines.map((l) => (l.kind, l.oldLine, l.newLine)), [
        (LineKind.context, 10, 10),
        (LineKind.add, null, 11),
        (LineKind.context, 11, 12),
      ]);
    });

    test('a count-less hunk header defaults both counts to one', () {
      final files = parseDiff('''
diff --git a/one.txt b/one.txt
--- a/one.txt
+++ b/one.txt
@@ -5 +5 @@
-a
+b
''');
      final h = files.single.hunks.single;
      expect((h.oldStart, h.oldCount, h.newStart, h.newCount), (5, 1, 5, 1));
    });

    test('a no-newline marker flags the last line of the hunk', () {
      final files = parseDiff('''
diff --git a/eol.txt b/eol.txt
--- a/eol.txt
+++ b/eol.txt
@@ -1 +1 @@
-old
+new
\\ No newline at end of file
''');
      final lines = files.single.hunks.single.lines;
      expect(lines, hasLength(2));
      expect(lines[0].noEol, isFalse);
      expect(lines[1].kind, LineKind.add);
      expect(lines[1].text, 'new');
      expect(lines[1].noEol, isTrue);
    });

    test('paths with spaces survive both header forms', () {
      final files = parseDiff('''
diff --git a/dir/my file.txt b/dir/my file.txt
index 1111111..2222222 100644
--- a/dir/my file.txt
+++ b/dir/my file.txt
@@ -1 +1 @@
-a
+b
''');
      final f = files.single;
      expect(f.path, 'dir/my file.txt');
      expect(f.oldPath, 'dir/my file.txt');
      expect(f.additions, 1);
      expect(f.deletions, 1);
    });

    test('several files in one text keep their order', () {
      final files = parseDiff('''
diff --git a/one.txt b/one.txt
--- a/one.txt
+++ b/one.txt
@@ -1 +1 @@
-a
+b
diff --git a/two.txt b/two.txt
--- a/two.txt
+++ b/two.txt
@@ -1 +1 @@
-c
+d
''');
      expect(files.map((f) => f.path), ['one.txt', 'two.txt']);
    });
  });
}
