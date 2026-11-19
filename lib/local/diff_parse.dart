/// Parses `git diff` output into files, hunks and lines.
///
/// Each line carries its old and new line numbers, so a GUI can jump from any
/// diff line to the file. Ported from the relay's `lua/vimos/diffparse.lua`,
/// minus the raw header/hunk lines (the models keep no such fields).
library;

import 'package:nvimos_poc/backend/models.dart';

final _gitHeader = RegExp(r'^diff --git a/(.*?) b/(.+)$');
final _hunkHeader = RegExp(r'^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@ ?(.*)$');

/// Parses unified diff text into [DiffFile]s, in the order they appear.
List<DiffFile> parseDiff(String text) {
  final files = <Map<String, Object?>>[];
  var file = <String, Object?>{};
  var hunks = <Map<String, Object?>>[];
  var hunk = <String, Object?>{};
  var inHunk = false;
  var oldN = 0;
  var newN = 0;

  for (final line in text.split('\n')) {
    if (line.startsWith('diff --git ')) {
      final m = _gitHeader.firstMatch(line);
      final a = m?.group(1);
      final b = m?.group(2);
      file = {
        'path': b ?? '',
        'old_path': a ?? '',
        'status': 'modified',
        'binary': false,
        'additions': 0,
        'deletions': 0,
        'hunks': hunks = <Map<String, Object?>>[],
      };
      files.add(file);
      inHunk = false;
    } else if (file.isNotEmpty && line.startsWith('@@ ')) {
      final m = _hunkHeader.firstMatch(line);
      final os = m?.group(1);
      final oc = m?.group(2);
      final ns = m?.group(3);
      final nc = m?.group(4);
      final sec = m?.group(5);
      hunk = {
        'header': line,
        'old_start': _num(os, 0),
        'old_count': _num(oc, 1),
        'new_start': _num(ns, 0),
        'new_count': _num(nc, 1),
        'section': sec ?? '',
        'lines': <Map<String, Object?>>[],
      };
      oldN = hunk['old_start']! as int;
      newN = hunk['new_start']! as int;
      hunks.add(hunk);
      inHunk = true;
    } else if (file.isNotEmpty && !inHunk) {
      if (line.startsWith('new file mode')) {
        file['status'] = 'added';
      } else if (line.startsWith('deleted file mode')) {
        file['status'] = 'deleted';
      } else if (line.startsWith('rename from ')) {
        file['old_path'] = line.substring(12);
        file['status'] = 'renamed';
      } else if (line.startsWith('rename to ')) {
        file['path'] = line.substring(10);
      } else if (line.startsWith('Binary files ') || line.startsWith('GIT binary patch')) {
        file['binary'] = true;
      } else if (line.startsWith('--- a/')) {
        file['old_path'] = line.substring(6);
      } else if (line.startsWith('+++ b/')) {
        file['path'] = line.substring(6);
      } else if (line == '--- /dev/null') {
        file['status'] = 'added';
      } else if (line == '+++ /dev/null') {
        file['status'] = 'deleted';
      }
    } else if (inHunk) {
      final c = line.isEmpty ? '' : line[0];
      final t = line.isEmpty ? '' : line.substring(1);
      final lines = hunk['lines']! as List<Map<String, Object?>>;
      if (c == ' ') {
        lines.add({'kind': 'context', 'text': t, 'old': oldN, 'new': newN});
        oldN++;
        newN++;
      } else if (c == '-') {
        lines.add({'kind': 'del', 'text': t, 'old': oldN});
        oldN++;
        file['deletions'] = (file['deletions']! as int) + 1;
      } else if (c == '+') {
        lines.add({'kind': 'add', 'text': t, 'new': newN});
        newN++;
        file['additions'] = (file['additions']! as int) + 1;
      } else if (c == '\\') {
        if (lines.isNotEmpty) lines.last['no_eol'] = true;
      }
    }
  }
  return [for (final f in files) DiffFile(f)];
}

/// A missing or empty group takes [fallback], as the Lua `num` helper does.
int _num(String? s, int fallback) {
  if (s == null || s.isEmpty) return fallback;
  return int.tryParse(s) ?? fallback;
}
