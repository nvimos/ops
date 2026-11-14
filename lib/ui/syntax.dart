import 'package:material_ui/material_ui.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/vim.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/ir-black.dart';

import '../backend/models.dart';
import 'theme.dart';

/// The language highlight.js knows a file by, from its name; null: no highlighting.
String? languageOf(String path) {
  final name = path.split('/').last.toLowerCase();
  if (name == 'makefile' || name == 'gnumakefile') return 'makefile';
  final dot = name.lastIndexOf('.');
  return dot < 0 ? null : _byExtension[name.substring(dot + 1)];
}

const _byExtension = {
  'dart': 'dart',
  'lua': 'lua',
  'md': 'markdown',
  'markdown': 'markdown',
  'yml': 'yaml',
  'yaml': 'yaml',
  'json': 'json',
  'xml': 'xml',
  'html': 'xml',
  'htm': 'xml',
  'svg': 'xml',
  'xaml': 'xml',
  'ps1': 'powershell',
  'psm1': 'powershell',
  'mk': 'makefile',
  'vim': 'vim',
  'sh': 'bash',
  'bash': 'bash',
  'py': 'python',
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'css': 'css',
  'c': 'cpp',
  'h': 'cpp',
  'cc': 'cpp',
  'cpp': 'cpp',
  'cxx': 'cpp',
  'hpp': 'cpp',
  'java': 'java',
  'kt': 'kotlin',
  'go': 'go',
  'rs': 'rust',
  'sql': 'sql',
  'toml': 'ini',
  'ini': 'ini',
  'cfg': 'ini',
};

final _engine = Highlight()
  ..registerLanguages({
    'bash': langBash,
    'cpp': langCpp,
    'css': langCss,
    'dart': langDart,
    'go': langGo,
    'ini': langIni,
    'java': langJava,
    'javascript': langJavascript,
    'json': langJson,
    'kotlin': langKotlin,
    'lua': langLua,
    'makefile': langMakefile,
    'markdown': langMarkdown,
    'powershell': langPowershell,
    'python': langPython,
    'rust': langRust,
    'sql': langSql,
    'typescript': langTypescript,
    'vim': langVim,
    'xml': langXml,
    'yaml': langYaml,
  });

/// The theme in use: highlight.js's ir-black, the closest bundled one to the Neovim colorscheme
/// (lunaperche: black, soft blue, gold, magenta). Swap for [ownSyntaxTheme] to go back.
const syntaxTheme = irBlackTheme;

/// The first palette (the `Syn` colors): style per highlight.js scope, color and emphasis only.
const ownSyntaxTheme = <String, TextStyle>{
  'keyword': TextStyle(color: Syn.keyword),
  'doctag': TextStyle(color: Syn.keyword),
  'meta-keyword': TextStyle(color: Syn.keyword),
  'selector-tag': TextStyle(color: Syn.keyword),
  'type': TextStyle(color: Syn.type),
  'built_in': TextStyle(color: Syn.type),
  'class': TextStyle(color: Syn.type),
  'title': TextStyle(color: Syn.title),
  'section': TextStyle(color: Syn.title, fontWeight: FontWeight.w600),
  'string': TextStyle(color: Syn.string),
  'char': TextStyle(color: Syn.string),
  'template-variable': TextStyle(color: Syn.string),
  'number': TextStyle(color: Syn.number),
  'literal': TextStyle(color: Syn.number),
  'symbol': TextStyle(color: Syn.number),
  'bullet': TextStyle(color: Syn.number),
  'comment': TextStyle(color: Syn.comment, fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Syn.comment, fontStyle: FontStyle.italic),
  'meta': TextStyle(color: Syn.meta),
  'tag': TextStyle(color: Syn.meta),
  'name': TextStyle(color: Syn.title),
  'attr': TextStyle(color: Syn.attr),
  'attribute': TextStyle(color: Syn.attr),
  'variable': TextStyle(color: Syn.attr),
  'property': TextStyle(color: Syn.attr),
  'regexp': TextStyle(color: Syn.regexp),
  'link': TextStyle(color: Syn.attr, decoration: TextDecoration.underline),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.w600),
};

/// The style of the innermost open scope that the theme knows; `title.function_` falls back to
/// `title`. Null: plain text.
TextStyle? _styleOf(List<String?> scopes) {
  for (final scope in scopes.reversed) {
    if (scope == null) continue;
    final style = syntaxTheme[scope] ?? syntaxTheme[scope.split('.').first];
    if (style != null) return style;
  }
  return null;
}

/// Collects what highlight.js emits as one list of spans per line, so a line of a diff can be drawn
/// on its own while the lines around it gave it its context (a comment or string over lines).
class _LineRenderer implements HighlightRenderer {
  final _scopes = <String?>[];
  final lines = <List<InlineSpan>>[<InlineSpan>[]];

  @override
  void openNode(DataNode node) => _scopes.add(node.scope);

  @override
  void closeNode(DataNode node) => _scopes.removeLast();

  @override
  void addText(String text) {
    final style = _styleOf(_scopes);
    final parts = text.split('\n');
    for (final (i, part) in parts.indexed) {
      if (i > 0) lines.add(<InlineSpan>[]);
      if (part.isNotEmpty) lines.last.add(TextSpan(text: part, style: style));
    }
  }
}

/// A hunk with a line this long is left plain: highlighting a minified file would stall a frame.
const _longLine = 1000;

/// The highlighted lines of one file's diff. Each hunk is highlighted when one of its lines is
/// first asked for, once for its old side (context and deletions) and once for its new side
/// (context and additions), and the result is kept.
class DiffSyntax {
  DiffSyntax(this.file) : language = languageOf(file.path) {
    for (final (i, h) in file.hunks.indexed) {
      for (final l in h.lines) {
        _hunkOf[l] = i;
      }
    }
  }

  final DiffFile file;
  final String? language;
  final _hunkOf = Map<DiffLine, int>.identity();
  final _spans = Map<DiffLine, TextSpan?>.identity();
  final _done = <int>{};

  /// The code of [l] with its colors, or null for plain text.
  TextSpan? spanOf(DiffLine l) {
    final i = _hunkOf[l];
    if (language == null || i == null) return null;
    if (_done.add(i)) _highlight(file.hunks[i]);
    return _spans[l];
  }

  void _highlight(Hunk h) {
    if (h.lines.any((l) => l.text.length > _longLine)) return;
    _side(h.lines.where((l) => l.kind != LineKind.add).toList(), oldSide: true);
    _side(h.lines.where((l) => l.kind != LineKind.del).toList(), oldSide: false);
  }

  /// Highlights [lines] as one text and stores the result of each line; context lines are stored
  /// from the new side only (the old side gives the deletions).
  void _side(List<DiffLine> lines, {required bool oldSide}) {
    final code = lines.map(_expanded).join('\n');
    try {
      final result = _engine.highlight(code: code, language: language!);
      final renderer = _LineRenderer();
      result.render(renderer);
      for (final (i, l) in lines.indexed) {
        if (oldSide && l.kind == LineKind.context) continue;
        final parts = i < renderer.lines.length ? renderer.lines[i] : <InlineSpan>[];
        _spans[l] = TextSpan(
          children: [...parts, if (l.noEol) const TextSpan(text: '  ⏎̸', style: TextStyle(color: C.faint))],
        );
      }
    } catch (_) {
      // an unreadable hunk stays plain
    }
  }

  static String _expanded(DiffLine l) => l.text.replaceAll('\t', '    ');
}
