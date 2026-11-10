// A small reader for the Markdown the planning files use: YAML front matter, `#`/`##`/`###`
// headings, checklists, bullets, fenced code. Every piece keeps its line number, so edits can
// target exact lines.

/// A checklist item `- [ ] text` / `- [x] text` at [line] (0-based).
class Check {
  Check(this.line, this.done, this.text, this.indent);
  final int line;
  final bool done;
  final String text;
  final int indent;
}

/// A `## Title` section: [start] is the heading line, body lines are (start, end).
class Section {
  Section(this.level, this.title, this.start, this.end);
  final int level;
  final String title;
  final int start;
  int end;
}

/// YAML front matter: a small subset (scalars, quoted strings, inline and block lists).
class FrontMatter {
  FrontMatter(this.values, this.keyLines, this.end);
  final Map<String, Object?> values;

  /// Line of each top-level key.
  final Map<String, int> keyLines;

  /// Line of the closing `---`, or -1 without front matter.
  final int end;

  String str(String key) => values[key] is String ? values[key] as String : (values[key]?.toString() ?? '');
  List<String> list(String key) =>
      values[key] is List ? (values[key] as List).map((e) => '$e').toList() : (str(key).isEmpty ? [] : [str(key)]);
}

final _checkRe = RegExp(r'^(\s*)[-*+] \[([ xX])\] (.*)$');
final _bulletRe = RegExp(r'^(\s*)[-*+] (.*)$');

Check? parseCheck(String line, int i) {
  final m = _checkRe.firstMatch(line);
  if (m == null) return null;
  return Check(i, m.group(2) != ' ', m.group(3)!.trim(), m.group(1)!.length);
}

String _unquote(String v) {
  v = v.trim();
  if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) return v.substring(1, v.length - 1).replaceAll("''", "'");
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) return v.substring(1, v.length - 1).replaceAll(r'\"', '"');
  return v;
}

FrontMatter parseFrontMatter(List<String> lines) {
  final values = <String, Object?>{};
  final keyLines = <String, int>{};
  if (lines.isEmpty || lines.first.trim() != '---') return FrontMatter(values, keyLines, -1);
  String? listKey;
  for (var i = 1; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim() == '---') return FrontMatter(values, keyLines, i);
    final item = RegExp(r'^\s+-\s+(.*)$').firstMatch(l);
    if (item != null && listKey != null) {
      (values[listKey] as List).add(_unquote(item.group(1)!));
      continue;
    }
    final kv = RegExp(r'^([A-Za-z_][\w-]*):\s*(.*)$').firstMatch(l);
    if (kv == null) continue;
    final key = kv.group(1)!;
    final raw = kv.group(2)!.trim();
    keyLines[key] = i;
    listKey = null;
    if (raw.isEmpty) {
      values[key] = <String>[];
      listKey = key;
    } else if (raw.startsWith('[') && raw.endsWith(']')) {
      final inner = raw.substring(1, raw.length - 1).trim();
      values[key] = inner.isEmpty ? <String>[] : inner.split(',').map(_unquote).toList();
    } else {
      values[key] = _unquote(raw);
    }
  }
  return FrontMatter(values, keyLines, -1);
}

/// Quote a YAML scalar if it needs it (the way Backlog.md writes titles).
String yamlScalar(String v) {
  if (v.isEmpty || RegExp(r'''[:#\[\]{}&*!|>'"%@`,]|^\s|\s$|^-''').hasMatch(v)) {
    return "'${v.replaceAll("'", "''")}'";
  }
  return v;
}

/// Headings outside fenced code. Each section runs to the next heading of the same or a higher
/// level (smaller number), or the end.
List<Section> parseSections(List<String> lines, {int from = 0}) {
  final out = <Section>[];
  var fence = false;
  for (var i = from; i < lines.length; i++) {
    final l = lines[i];
    if (l.trimLeft().startsWith('```')) {
      fence = !fence;
      continue;
    }
    if (fence) continue;
    final m = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$').firstMatch(l);
    if (m == null) continue;
    final level = m.group(1)!.length;
    for (final s in out.reversed) {
      if (s.end == lines.length && s.level >= level) s.end = i;
    }
    out.add(Section(level, m.group(2)!, i, lines.length));
  }
  return out;
}

Section? findSection(List<Section> sections, bool Function(String title) test, {int? level}) {
  for (final s in sections) {
    if ((level == null || s.level == level) && test(s.title.toLowerCase())) return s;
  }
  return null;
}

/// Checklist items in a section body (outside code fences).
List<Check> checksIn(List<String> lines, Section? s) {
  if (s == null) return [];
  final out = <Check>[];
  var fence = false;
  for (var i = s.start + 1; i < s.end; i++) {
    if (lines[i].trimLeft().startsWith('```')) {
      fence = !fence;
      continue;
    }
    if (fence) continue;
    final c = parseCheck(lines[i], i);
    if (c != null) out.add(c);
  }
  return out;
}

/// A block of a section body, for rendering without Markdown syntax.
sealed class Block {}

class Para extends Block {
  Para(this.text);
  final String text;
}

class Bullet extends Block {
  Bullet(this.text, this.indent);
  final String text;
  final int indent;
}

class CheckBlock extends Block {
  CheckBlock(this.check);
  final Check check;
}

class CodeBlock extends Block {
  CodeBlock(this.lang, this.lines);
  final String lang;
  final List<String> lines;
}

class SubHeading extends Block {
  SubHeading(this.text, this.level);
  final String text;
  final int level;
}

/// Body of a section (or a whole file from [from]) as blocks: paragraphs (joined lines),
/// bullets, checks, code, sub-headings.
List<Block> blocksIn(List<String> lines, int from, int to) {
  final out = <Block>[];
  final para = <String>[];
  void flush() {
    if (para.isNotEmpty) {
      out.add(Para(para.join(' ')));
      para.clear();
    }
  }

  for (var i = from; i < to; i++) {
    final l = lines[i];
    if (l.trimLeft().startsWith('```')) {
      flush();
      final lang = l.trimLeft().substring(3).trim();
      final code = <String>[];
      i++;
      while (i < to && !lines[i].trimLeft().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      out.add(CodeBlock(lang, code));
      continue;
    }
    if (l.trim().isEmpty) {
      flush();
      continue;
    }
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(l);
    if (h != null) {
      flush();
      out.add(SubHeading(h.group(2)!.trim(), h.group(1)!.length));
      continue;
    }
    final c = parseCheck(l, i);
    if (c != null) {
      flush();
      out.add(CheckBlock(c));
      continue;
    }
    final b = _bulletRe.firstMatch(l);
    if (b != null) {
      flush();
      out.add(Bullet(b.group(2)!.trim(), b.group(1)!.length));
      continue;
    }
    if (l.startsWith('    ') && para.isEmpty) {
      out.add(CodeBlock('', [l.trim()]));
      continue;
    }
    if (out.isNotEmpty && out.last is Bullet && para.isEmpty && l.startsWith('  ')) {
      final last = out.removeLast() as Bullet;
      out.add(Bullet('${last.text} ${l.trim()}', last.indent));
      continue;
    }
    para.add(l.trim());
  }
  flush();
  return out;
}
