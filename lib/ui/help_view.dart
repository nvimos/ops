import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../timing/ui_timing.dart';
import 'theme.dart';
import 'widgets.dart';

/// The keys the app has, by where they work (PLAN.md "Keys" is the full draft).
const keyTable = [
  (
    'Everywhere',
    [
      ('Alt+[]', 'previous or next mode (also the mouse wheel on the rail)'),
      ('Alt+1…9', 'mode by its place on the rail'),
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
      ('o', 'open it in Neovim (not local)'),
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
      ('Z', 'next view: unified, side-by-side, merge (PR, Changes; the view bar has a button for each)'),
      ('zw', 'toggle text wrapping'),
      ('zh', 'toggle hunk headers'),
      ('Enter', 'on a commit: show only that commit'),
      ('Esc', 'back from one commit to all commits'),
    ],
  ),
  (
    'Changes',
    [
      ('C', 'go to the branch switcher and open its list (any mode)'),
      ('gi', 'go to the branch input, without opening its list'),
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
  ('Repos', [('Enter', 'make it the Active Directory'), ('/', 'filter'), ('n', 'New Neovim per directory')]),
  (
    'Add and Ignore',
    [
      ('t  u', 'add or untrack the highlighted'),
      ('i  I', 'ignore: dialog, or at once (a tracked row is untracked too)'),
      ('x  p  v  r', 'delete; the side pane: ignore panes or preview; reload'),
      ('Space  Ctrl+A', 'highlight the row, every row'),
    ],
  ),
  (
    'Ignore panes',
    [
      ('Tab', 'the .gitignore list, then the lines'),
      ('jk, sw, {up}{down}', 'pick a file, or move the line cursor'),
      ('hl, ad, {left}{right}', 'between the file list and the lines'),
      ('Ctrl+{left}{right}', 'jump between the panes'),
      ('Enter', 'open the file, or the line, in the editor'),
      ('Delete', 'delete the line (the notice has Undo)'),
      ('Shift+wheel', 'scroll the lines'),
      ('Right click', 'a line: Delete, Dirname, Flip, Open'),
    ],
  ),
  (
    'Ignore dialog',
    [
      ('1 2 3  f x d', 'scope: this file, this extension, this folder'),
      ('j  k', 'where the rule goes'),
      ('Enter  Esc', 'write the rule, close without writing'),
    ],
  ),
  (
    'Mouse',
    [
      ('Shift+wheel', 'Facets, task list: item'),
      ('Middle click', 'Facets, task list: wheel steps items or scrolls'),
      ('Click', 'pick or select; checkbox ticks; Active Directory again: Tasks'),
      ('Right click,Ctrl+click', 'checkbox: next mark'),
      ('Ctrl+click', 'task: open its file in nvim-qt'),
      ('Back', 'the previous place: a task link, a mode switch, a markdown link'),
      ('Forward', 'redo the jump Back undid (a markdown link)'),
      ('Click a markdown or HTML link', 'preview: another page shows there; a web link opens in the browser'),
      ('Drag a rail icon', 'reorder the modes; the order is remembered'),
      ('Right click a rail icon', 'hide that mode; Settings shows it again'),
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

  /// The least a column may be, at rest and while the window edge moves; below this the table is
  /// kept and its right edge is clipped.
  static const _minColumnWidth = 250.0;

  /// The padding of the table around its columns (20 left, 20 right).
  static const _padding = 40.0;

  final _search = TextEditingController();
  final _focus = FocusNode(debugLabel: 'help search');

  /// The heights of the key groups: the split depends on them, not on the width.
  late final _heights = [for (final g in keyTable) g.$2.length + 2];

  /// The table cached for a column count and query. A width change inside the same structure only
  /// needs a new layout; one across columns rebuilds it.
  int? _columnCount;
  String _columnQuery = '';
  Widget? _columnArea;

  /// The width the cached table was laid out for, and the window width it last settled at.
  double _layoutWidth = 0, _settledWidth = 0, _latestWidth = 0;

  /// A window drag: the table is frozen, scaled to the new width, and reflowed once the width has
  /// been still for [quiet]. There is no reliable end event for a window resize.
  bool _resizing = false;
  Timer? _resizeTimer;
  static const quiet = Duration(milliseconds: 150);

  /// The frame time of a width change that reflowed at once. A one-off jump (the rail toggled, a
  /// side pane opened) reflows directly; only a second change within [quiet] starts the freeze.
  /// The frame timestamp, not a Stopwatch: widget tests advance the frame clock with `pump`.
  Duration? _recentChangeAt;

  /// A width change is being timed, from the new layout to the frame on screen (`help.resize`).
  Span? _resize;

  @override
  void dispose() {
    _resizeTimer?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// `/`: empty the field and the highlights, and type in the field.
  /// `gi`: the search field, its text kept.
  void focusSearch() => _focus.requestFocus();

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
      PaneHeader(title: const Text('Keys'), trailing: [Flexible(child: _field())]),
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

  static int _countFor(double width) => (width ~/ _columnWidth).clamp(1, keyTable.length);

  static double _floorWidth(int count) => count * _minColumnWidth + _padding;

  /// Build the table for [count] columns at [width] (already at or above the 250 px floor).
  void _build(int count, double width, {required bool compact}) {
    _columnCount = count;
    _columnQuery = _search.text;
    _layoutWidth = width;
    _columnArea = SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(_padding / 2, 4, _padding / 2, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in splitColumns(_heights, count))
              Expanded(child: _KeyColumn(groups: c, query: _columnQuery, compact: compact)),
          ],
        ),
      ),
    );
  }

  /// Lay the table out for the current width: the normal, wrapping rows, at the column count the
  /// width allows and never narrower than the 250 px floor.
  void _settle(double width) {
    _resizeTimer?.cancel();
    _resizeTimer = null;
    final count = _countFor(width);
    _build(count, max(width, _floorWidth(count)), compact: false);
    _resizing = false;
    _settledWidth = width;
  }

  void _reflow() {
    if (mounted) setState(() => _settle(_latestWidth));
  }

  Widget _columns(double width) {
    _latestWidth = width;
    if (_columnArea == null || _columnQuery != _search.text) {
      _settle(width);
    } else if (!_resizing && width != _settledWidth) {
      _timeResize();
      final now = SchedulerBinding.instance.currentFrameTimeStamp;
      final recent = _recentChangeAt;
      if (recent != null && now - recent < quiet) {
        // A second change within [quiet]: a drag. Rebuild the frozen table once with one-line
        // descriptions, then every further frame only scales it.
        _recentChangeAt = null;
        _resizing = true;
        _build(_columnCount!, _layoutWidth, compact: true);
      } else {
        // A single change reflows at once, as at rest.
        _settle(width);
        _recentChangeAt = now;
      }
    }
    if (_resizing) {
      _resizeTimer?.cancel();
      _resizeTimer = Timer(quiet, _reflow);
    }
    return _shown(width);
  }

  /// Time this width change (a direct reflow or the start of a drag) to the frame on screen.
  void _timeResize() {
    if (_resize != null) return;
    final span = _resize = UiTiming.instance.span('help.resize');
    WidgetsBinding.instance.addPostFrameCallback((_) => _resize = null);
    span.markPainted();
  }

  /// The table, scaled uniformly to [width] while the drag goes on; when nothing is being dragged
  /// it is the layout itself, clipped at the right when the floor makes it wider than the window.
  Widget _shown(double width) {
    final area = _columnArea!;
    final layout = _layoutWidth;
    if (!_resizing && layout == width) return area;
    final target = max(width, _floorWidth(_columnCount ?? 1));
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: layout,
        maxWidth: layout,
        child: _resizing
            ? Transform.scale(scale: target / layout, alignment: Alignment.topLeft, child: area)
            : area,
      ),
    );
  }
}

class _KeyColumn extends StatelessWidget {
  const _KeyColumn({required this.groups, required this.query, this.compact = false});

  final List<int> groups;
  final String query;

  /// One line per description (a window drag): fixed row heights, no wrapping to re-layout.
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in groups)
          _KeyGroup(title: keyTable[i].$1, keys: keyTable[i].$2, query: query, compact: compact),
      ],
    ),
  );
}

class _KeyGroup extends StatelessWidget {
  const _KeyGroup({required this.title, required this.keys, required this.query, this.compact = false});

  final String title, query;
  final List<(String, String)> keys;

  /// One line per description (a window drag).
  final bool compact;

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
        children: [for (final (key, what) in keys) _row(key, what, query, compact)],
      ),
    ],
  );

  static TableRow _row(String keys, String what, String query, bool compact) => TableRow(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 12, 2),
        child: KeyLabel(keys, query: query),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(
          TextSpan(children: highlight(what, query)),
          style: T.small,
          maxLines: compact ? 1 : null,
          overflow: compact ? TextOverflow.ellipsis : TextOverflow.clip,
        ),
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
