/// Parses `git diff` output into files, hunks and lines.
///
/// Each line carries its old and new line numbers, so a GUI can jump from any
/// diff line to the file. Ported from the relay's `lua/vimos/diffparse.lua`,
/// minus the raw header/hunk lines (the models keep no such fields).
///
/// A diff-header token is raw text or a double-quoted C string around the whole
/// `a/path` or `b/path`. Quoted paths are unquoted, octal escapes as UTF-8, so a
/// hunk is filed under the real name. A hunk patch quotes a path that needs it.
library;

import 'dart:convert';

import 'package:nvimos_poc/backend/models.dart';

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
      final sides = _headerSides(line);
      file = {
        'path': sides?.path ?? '',
        'old_path': sides?.oldPath ?? '',
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
        final p = _plainOrUnquoted(line.substring(12));
        if (p != null) {
          file['old_path'] = p;
          file['status'] = 'renamed';
        }
      } else if (line.startsWith('rename to ')) {
        final p = _plainOrUnquoted(line.substring(10));
        if (p != null) file['path'] = p;
      } else if (line.startsWith('Binary files ') || line.startsWith('GIT binary patch')) {
        file['binary'] = true;
      } else if (line == '--- /dev/null' || line.startsWith('--- /dev/null\t')) {
        file['status'] = 'added';
      } else if (line == '+++ /dev/null' || line.startsWith('+++ /dev/null\t')) {
        file['status'] = 'deleted';
      } else if (line.startsWith('--- ')) {
        final p = _minusPlusPath(line.substring(4));
        if (p != null) file['old_path'] = p;
      } else if (line.startsWith('+++ ')) {
        final p = _minusPlusPath(line.substring(4));
        if (p != null) file['path'] = p;
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

/// One hunk as a patch `git apply` can take, with the file's own headers.
///
/// A path with a space, or a byte git quotes, is quoted on the `diff --git`
/// line and the `---` / `+++` lines. A plain path, and `/dev/null`, stay bare.
String hunkPatch(DiffFile file, Hunk h) {
  final oldPath = file.oldPath.isEmpty ? file.path : file.oldPath;
  final from = file.status == 'added' ? '/dev/null' : 'a/$oldPath';
  final to = file.status == 'deleted' ? '/dev/null' : 'b/${file.path}';
  final buf = StringBuffer()
    ..writeln('diff --git ${_quoteGitSide('a/$oldPath')} ${_quoteGitSide('b/${file.path}')}')
    ..writeln('--- ${_quoteGitSide(from)}')
    ..writeln('+++ ${_quoteGitSide(to)}')
    ..writeln(h.header);
  for (final line in h.lines) {
    buf.write(switch (line.kind) {
      LineKind.context => ' ',
      LineKind.add => '+',
      LineKind.del => '-',
    });
    buf.writeln(line.text);
    if (line.noEol) buf.writeln('\\ No newline at end of file');
  }
  return buf.toString();
}

/// A missing or empty group takes [fallback], as the Lua `num` helper does.
int _num(String? s, int fallback) {
  if (s == null || s.isEmpty) return fallback;
  return int.tryParse(s) ?? fallback;
}

class _Sides {
  _Sides(this.oldPath, this.path);
  final String oldPath;
  final String path;
}

class _Quoted {
  _Quoted(this.value, this.end);
  final String value;

  /// Index just after the closing quote.
  final int end;
}

/// The two paths of a `diff --git` line, or null if the line does not carry them.
///
/// An unquoted line splits on the first ` b/`, as the old `a/(.*?) b/(.+)` match
/// did, including a space in the middle of a path. A quoted token is a C string.
_Sides? _headerSides(String line) {
  const mark = 'diff --git ';
  if (!line.startsWith(mark)) return null;
  final rest = line.substring(mark.length);
  if (rest.startsWith('"')) {
    final first = _unquoteC(rest);
    if (first == null || first.end >= rest.length || rest[first.end] != ' ') return null;
    final secondRest = rest.substring(first.end + 1);
    final String second;
    if (secondRest.startsWith('"')) {
      final q = _unquoteC(secondRest);
      if (q == null) return null;
      second = q.value;
    } else {
      second = secondRest;
    }
    return _Sides(_sidePath(first.value, 'a/'), _sidePath(second, 'b/'));
  }
  if (!rest.startsWith('a/')) return null;
  final quotedSecond = rest.indexOf(' "');
  final plainSecond = rest.indexOf(' b/');
  if (quotedSecond >= 0 && (plainSecond < 0 || quotedSecond < plainSecond)) {
    final q = _unquoteC(rest.substring(quotedSecond + 1));
    if (q == null) return null;
    return _Sides(rest.substring(2, quotedSecond), _sidePath(q.value, 'b/'));
  }
  if (plainSecond < 0) return null;
  return _Sides(rest.substring(2, plainSecond), rest.substring(plainSecond + 3));
}

/// Strip [prefix] (`a/` or `b/`) when the token has it.
String _sidePath(String token, String prefix) =>
    token.startsWith(prefix) ? token.substring(prefix.length) : token;

/// A `rename from` / `rename to` path. No `a/` or `b/` prefix. Null if a quote
/// does not close, so a failed unquote does not wipe the header path.
String? _plainOrUnquoted(String rest) {
  if (rest.startsWith('"')) return _unquoteC(rest)?.value;
  return rest;
}

/// Path from the text after `--- ` or `+++ `. Null when the line is not a path
/// or a quote does not unquote, so it cannot replace a path already taken.
String? _minusPlusPath(String rest) {
  if (rest.startsWith('"')) {
    final u = _unquoteC(rest);
    if (u == null) return null;
    if (u.value.startsWith('a/') || u.value.startsWith('b/')) return u.value.substring(2);
    return u.value;
  }
  if (!rest.startsWith('a/') && !rest.startsWith('b/')) return null;
  final tab = rest.indexOf('\t');
  final raw = tab < 0 ? rest : rest.substring(0, tab);
  return raw.substring(2);
}

/// Unquote a git C string starting at the opening quote. Octal bytes are UTF-8.
_Quoted? _unquoteC(String text) {
  if (text.isEmpty || text.codeUnitAt(0) != 0x22) return null;
  final bytes = <int>[];
  var i = 1;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (c == 0x22) {
      return _Quoted(utf8.decode(bytes, allowMalformed: true), i + 1);
    }
    if (c == 0x5c && i + 1 < text.length) {
      final n = text.codeUnitAt(i + 1);
      final mapped = _namedUnescape[n];
      if (mapped != null) {
        bytes.add(mapped);
        i += 2;
        continue;
      }
      if (n >= 0x30 && n <= 0x37) {
        var val = 0;
        var digits = 0;
        var j = i + 1;
        while (digits < 3 && j < text.length) {
          final d = text.codeUnitAt(j);
          if (d < 0x30 || d > 0x37) break;
          val = (val << 3) + (d - 0x30);
          digits++;
          j++;
        }
        bytes.add(val & 0xff);
        i = j;
        continue;
      }
      bytes.add(n & 0xff);
      i += 2;
      continue;
    }
    if (c < 0x80) {
      bytes.add(c);
    } else {
      bytes.addAll(utf8.encode(String.fromCharCode(c)));
    }
    i++;
  }
  return null;
}

/// Named C escapes git prints, as the byte they stand for.
const _namedUnescape = {
  0x5c: 0x5c, // \
  0x22: 0x22, // "
  0x6e: 0x0a, // n
  0x74: 0x09, // t
  0x72: 0x0d, // r
  0x61: 0x07, // a
  0x62: 0x08, // b
  0x76: 0x0b, // v
  0x66: 0x0c, // f
};

const _namedEscape = {
  0x5c: r'\\',
  0x22: r'\"',
  0x07: r'\a',
  0x08: r'\b',
  0x09: r'\t',
  0x0a: r'\n',
  0x0b: r'\v',
  0x0c: r'\f',
  0x0d: r'\r',
};

/// Quote [side] (`a/path`, `b/path`, or `/dev/null`) the way `git apply` reads it.
///
/// Git's own diff leaves a space bare and quotes a non-ASCII byte as octal.
/// A space is quoted too: that is the hunk `git apply` must still accept.
String _quoteGitSide(String side) {
  final bytes = utf8.encode(side);
  var needs = false;
  for (final b in bytes) {
    if (b <= 0x20 || b == 0x7f || b == 0x22 || b == 0x5c || b >= 0x80) {
      needs = true;
      break;
    }
  }
  if (!needs) return side;
  final out = StringBuffer('"');
  for (final b in bytes) {
    final named = _namedEscape[b];
    if (named != null) {
      out.write(named);
    } else if (b < 0x20 || b == 0x7f || b >= 0x80) {
      out.write('\\${(b >> 6) & 7}${(b >> 3) & 7}${b & 7}');
    } else {
      out.writeCharCode(b);
    }
  }
  out.write('"');
  return out.toString();
}
