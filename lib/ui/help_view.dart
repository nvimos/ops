import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'widgets.dart';

/// The keys the app has, by where they work (PLAN.md "Keys" is the full draft).
const keyTable = [
  (
    'Everywhere',
    [
      ('Alt+[]', 'previous or next mode (also the mouse wheel on the rail)'),
      ('Alt+1…5', 'mode by its place on the rail'),
      ('Ctrl+B', 'expand or collapse the sidebar'),
      ('?', 'this list (the Help mode)'),
      ('b', 'show or hide the debug bar'),
      ('Tab', 'next element'),
      ('Shift+Tab', 'previous element'),
      ('Ctrl+{up}{down}{left}{right}', 'jump to the pane in that direction'),
    ],
  ),
  (
    'Any list',
    [
      ('jk, sw, {up}{down}', 'navigate'),
      ('Shift+{up}{down}, JK', 'scroll fast'),
      ('gg  G', 'first or last item'),
      ('{ }', 'three items up or down in a list'),
      ('Ctrl+DU', 'half a page down or up'),
      ('Enter', 'open or pick the item'),
      ('o', 'open the item in Neovim'),
      ('hl, ad, {left}{right}', 'navigate'),
      ('WASD', 'as the arrows (Tasks and Directories: only w and s, no panes)'),
    ],
  ),
  (
    'Pull request',
    [
      ('i  gi', 'go to the base input'),
      ('2gi', 'go to the head input'),
      ('gs', 'swap base and head'),
      ('[f  ]f', 'previous or next file'),
      ('[c  ]c', 'previous or next hunk'),
      ('zc  zo', "fold or unfold the file's folder"),
      ('zR  zM', 'expand or collapse all folders (PR, Changes)'),
      ('v', 'unified or side-by-side (PR, Changes)'),
      ('zw', 'toggle text wrapping'),
      ('zh', 'toggle hunk headers'),
      ('Enter', 'on a commit: show only that commit'),
      ('Esc', 'back from one commit to all commits'),
    ],
  ),
  (
    'Changes',
    [
      ('C  gb', 'go to the branch switcher and open its list (C: any mode)'),
      ('[c  ]c', 'previous or next hunk'),
      ('-', 'stage or unstage the hunk, or the file'),
      ('Space  u', 'stage or unstage the hunk, or the file'),
      ('X', 'discard (asks first)'),
      ('cc', 'write the commit message'),
      ('Ctrl+Enter', 'commit (in the message)'),
      ('Esc', 'back from the message to the files'),
    ],
  ),
  (
    'Tasks',
    [
      ('/', 'filter'),
      ('Esc', 'close the detail panel'),
      ('.', 'widen or narrow the detail panel'),
      ('c  t  p', 'new task, cycle status, cycle priority'),
      ('Ctrl+K', 'command palette'),
      ('Shift+A', 'filter only this or all projects'),
    ],
  ),
  ('Directories', [('Enter', 'make it the Active Directory'), ('/', 'filter'), ('n', 'New Neovim per directory')]),
  (
    'Mouse',
    [
      ('Shift+wheel', 'Facets, task list: item'),
      ('Middle click', 'Facets, task list: wheel steps items or scrolls'),
      ('Click', 'pick or select; checkbox ticks; Active Directory again: Tasks'),
      ('Right click,Ctrl+click', 'checkbox: next mark'),
      ('Ctrl+click', 'task: open its file in nvim-qt'),
    ],
  ),
];

/// Splits the key groups, in order, into at most [columns] columns so the tallest is lowest.
List<List<int>> splitColumns(List<int> heights, int columns) {
  final all = [for (var i = 0; i < heights.length; i++) i];
  if (columns <= 1 || heights.length <= 1) return heights.isEmpty ? [] : [all];
  var best = <List<int>>[];
  var bestHeight = double.infinity;
  for (var first = 1; first <= heights.length; first++) {
    final head = [for (var i = 0; i < first; i++) i];
    final rest = splitColumns(heights.sublist(first), columns - 1);
    final columnsHere = [
      head,
      for (final c in rest) [for (final i in c) i + first],
    ];
    final tallest = columnsHere.map((c) => c.fold(0, (a, i) => a + heights[i])).reduce(max);
    if (tallest < bestHeight) (best, bestHeight) = (columnsHere, tallest.toDouble());
  }
  return best;
}

/// The Help mode: every key the app has, by where it works, in as many columns as fit.
/// `/` starts a search: the field takes the keyboard, and the text that matches what is typed is
/// highlighted; `/` again clears the field and the highlights.
class HelpView extends StatefulWidget {
  const HelpView({super.key, this.onLeave});

  /// Gives the keyboard back to the app (Esc or Enter in the search field).
  final VoidCallback? onLeave;

  @override
  State<HelpView> createState() => HelpViewState();
}

class HelpViewState extends State<HelpView> {
  static const _columnWidth = 360.0;

  final _search = TextEditingController();
  final _focus = FocusNode(debugLabel: 'help search');

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// `/`: empty the field and the highlights, and type in the field.
  void startSearch() {
    _search.clear();
    setState(() {});
    _focus.requestFocus();
  }

  /// A key typed anywhere in Help: it starts (or goes on with) the search, and the field takes the
  /// keyboard.
  void type(String ch) {
    _search.text += ch;
    _search.selection = TextSelection.collapsed(offset: _search.text.length);
    setState(() {});
    _focus.requestFocus();
  }

  void _leave({required bool clear}) {
    if (clear) _search.clear();
    setState(() {});
    widget.onLeave?.call();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PaneHeader(title: const Text('Keys'), trailing: [_field()]),
      Expanded(child: LayoutBuilder(builder: (context, box) => _columns(box.maxWidth))),
    ],
  );

  Widget _field() => SizedBox(
    width: 240,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.slash): startSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () => _leave(clear: true),
      },
      child: ClearOnAltX(
        controller: _search,
        onCleared: (_) => setState(() {}),
        child: TextField(
          controller: _search,
          focusNode: _focus,
          style: T.body,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 15, color: C.muted),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            suffixIcon: ClearButton(controller: _search, onCleared: (_) => setState(() {})),
            suffixIconConstraints: ClearButton.constraints,
            hintText: 'Search (/)',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _leave(clear: false),
        ),
      ),
    ),
  );

  Widget _columns(double width) {
    final count = (width ~/ _columnWidth).clamp(1, keyTable.length);
    final columns = splitColumns([for (final g in keyTable) g.$2.length + 2], count);
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in columns)
              Expanded(
                child: _KeyColumn(groups: c, query: _search.text),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyColumn extends StatelessWidget {
  const _KeyColumn({required this.groups, required this.query});

  final List<int> groups;
  final String query;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final i in groups) _KeyGroup(title: keyTable[i].$1, keys: keyTable[i].$2, query: query)],
    ),
  );
}

class _KeyGroup extends StatelessWidget {
  const _KeyGroup({required this.title, required this.keys, required this.query});

  final String title, query;
  final List<(String, String)> keys;

  /// The key column is as wide as the group's widest key: descriptions sit right after their keys,
  /// and still line up inside the group.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text.rich(TextSpan(children: highlight(title.toUpperCase(), query)), style: T.section),
      ),
      Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [for (final (key, what) in keys) _row(key, what, query)],
      ),
    ],
  );

  static TableRow _row(String keys, String what, String query) => TableRow(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 12, 2),
        child: KeyLabel(keys, query: query),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(TextSpan(children: highlight(what, query)), style: T.small),
      ),
    ],
  );
}

/// A key label. Every key, the named ones (Enter, Space, Alt, Esc, ...) and the arrows included, is
/// drawn in the accent colour, so they stand out from the letter keys, which stay
/// plain text. `{up}` `{down}` `{left}` `{right}` in the label are the arrows. Keys that go
/// together are written next to each other ("jk", "hl"), without a slash between them.
class KeyLabel extends StatelessWidget {
  const KeyLabel(this.label, {super.key, this.query = ''});

  final String label;

  /// Text to highlight (the Help search).
  final String query;

  static const arrows = {
    'up': Icons.keyboard_arrow_up,
    'down': Icons.keyboard_arrow_down,
    'left': Icons.keyboard_arrow_left,
    'right': Icons.keyboard_arrow_right,
  };

  /// The keys drawn in the accent colour.
  static const named = ['Alt', 'Ctrl', 'Shift', 'Enter', 'Esc', 'Space', 'Tab', 'click'];

  static final _token = RegExp(r'\{(up|down|left|right)\}|' + named.join('|'));

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: T.code.copyWith(color: C.accent),
      children: spans(label, query: query),
    ),
  );

  /// The label cut at its special keys: plain text, accent-coloured names and arrow icons.
  static List<InlineSpan> spans(String label, {String query = ''}) {
    final out = <InlineSpan>[];
    var from = 0;
    for (final m in _token.allMatches(label)) {
      if (m.start > from) out.addAll(_plain(label.substring(from, m.start), query));
      final arrow = m[1];
      out.add(
        arrow == null
            ? TextSpan(
                children: highlight(m[0]!, query),
                style: const TextStyle(color: C.accent),
              )
            : WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(arrows[arrow], size: 14, color: C.accent),
              ),
      );
      from = m.end;
    }
    if (from < label.length) out.addAll(_plain(label.substring(from), query));
    return out;
  }

  /// Plain text; the `+` that joins keys (Ctrl+B) and the `,` between alternatives are drawn in the
  /// border colour, nearly the background's, so they don't compete with the keys.
  static List<InlineSpan> _plain(String text, String query) => [
    for (final part in text.split(RegExp(r'(?=[+,])|(?<=[+,])')))
      if (part == '+' || part == ',')
        TextSpan(
          text: part,
          style: const TextStyle(color: C.border),
        )
      else
        ...highlight(part, query),
  ];
}

/// [text] with every case-insensitive occurrence of [query] marked (a coloured background); the
/// text as it is when [query] is empty.
List<InlineSpan> highlight(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final out = <InlineSpan>[];
  var from = 0;
  for (var at = lower.indexOf(q); at >= 0; at = lower.indexOf(q, from)) {
    if (at > from) out.add(TextSpan(text: text.substring(from, at)));
    out.add(
      TextSpan(
        text: text.substring(at, at + q.length),
        style: const TextStyle(backgroundColor: C.found),
      ),
    );
    from = at + q.length;
  }
  if (from < text.length) out.add(TextSpan(text: text.substring(from)));
  return out;
}
