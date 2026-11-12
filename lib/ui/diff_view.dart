import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../backend/models.dart';
import 'file_tree.dart';
import 'theme.dart';
import 'widgets.dart';

/// Called with a line number and whether it is on the old side (deletions).
typedef OnDiffLine = void Function(int line, bool isOld);

/// A diff of one file, unified or side-by-side: hunk headers, old/new line numbers, colored lines.
/// Clicking a line calls [onLine]; [hunkActions] adds buttons to a hunk header (stage, discard,
/// ...); [headerActions] go to the right of the file name; [side] shows to the right of the diff.
class DiffView extends StatelessWidget {
  const DiffView({
    super.key,
    required this.file,
    this.onLine,
    this.hunkActions,
    this.headerActions = const [],
    this.side,
    this.sideBySide = false,
    this.wrap = true,
    this.hunk = -1,
  });

  final DiffFile file;
  final OnDiffLine? onLine;
  final List<Widget> Function(Hunk hunk)? hunkActions;
  final List<Widget> headerActions;
  final bool sideBySide;

  /// Long lines wrap; off: they stay on one line (unified: scroll sideways; side-by-side: clipped).
  final bool wrap;
  final Widget? side;

  /// The current hunk (]c / [c): scrolled into view and highlighted; -1 for none.
  final int hunk;

  @override
  Widget build(BuildContext context) {
    final body = _DiffBody(file: file, rows: diffRows(file, sideBySide: sideBySide), view: this);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(title: _FileTitle(file), trailing: headerActions),
        Expanded(child: side == null ? body : _WithSide(body: body, side: side!)),
      ],
    );
  }
}

// Model ---------------------------------------------------------------------------------------------

/// One row of a diff: a hunk header, a unified line, or a side-by-side pair (either side may be
/// blank).
sealed class DiffRow {}

class HunkRow extends DiffRow {
  HunkRow(this.hunk);
  final Hunk hunk;
}

class LineRow extends DiffRow {
  LineRow(this.line);
  final DiffLine line;
}

class PairRow extends DiffRow {
  PairRow(this.left, this.right);
  final DiffLine? left, right;
}

/// The rows to show for [file]. Side by side: context on both sides; each run of deletions paired
/// with the run of additions after it.
List<DiffRow> diffRows(DiffFile file, {required bool sideBySide}) => [
  for (final h in file.hunks) ...[
    HunkRow(h),
    if (sideBySide) ..._pairs(h.lines) else ...h.lines.map(LineRow.new),
  ],
];

List<DiffRow> _pairs(List<DiffLine> lines) {
  final out = <DiffRow>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].kind == LineKind.context) {
      out.add(PairRow(lines[i], lines[i]));
      i++;
      continue;
    }
    final dels = <DiffLine>[], adds = <DiffLine>[];
    while (i < lines.length && lines[i].kind == LineKind.del) {
      dels.add(lines[i++]);
    }
    while (i < lines.length && lines[i].kind == LineKind.add) {
      adds.add(lines[i++]);
    }
    for (var k = 0; k < math.max(dels.length, adds.length); k++) {
      out.add(PairRow(k < dels.length ? dels[k] : null, k < adds.length ? adds[k] : null));
    }
  }
  return out;
}

String _shown(DiffLine l) => l.text.replaceAll('\t', '    ') + (l.noEol ? '  ⏎̸' : '');

/// Colors and sign of a line kind.
typedef LineLook = ({Color bg, Color gutter, String sign, Color signColor});

LineLook lookOf(LineKind k) => switch (k) {
  LineKind.add => (bg: C.addBg, gutter: C.addGutter, sign: '+', signColor: C.green),
  LineKind.del => (bg: C.delBg, gutter: C.delGutter, sign: '−', signColor: C.red),
  LineKind.context => (bg: Colors.transparent, gutter: Colors.transparent, sign: ' ', signColor: C.faint),
};

// Organisms -----------------------------------------------------------------------------------------

/// The scrolling rows, or a message for binary and empty diffs. Unwrapped unified lines get a
/// sideways scroll as wide as the longest line. Scrolls the current hunk into view.
class _DiffBody extends StatefulWidget {
  const _DiffBody({required this.file, required this.rows, required this.view});

  final DiffFile file;
  final List<DiffRow> rows;
  final DiffView view;

  @override
  State<_DiffBody> createState() => _DiffBodyState();
}

class _DiffBodyState extends State<_DiffBody> {
  final _scroll = ScrollController();
  final _hunkKey = GlobalKey();

  /// A rough row height, to bring a far hunk near before it is built and can be scrolled exactly.
  static const _approxRow = 18.0;

  @override
  void didUpdateWidget(_DiffBody old) {
    super.didUpdateWidget(old);
    if (widget.view.hunk != old.view.hunk || widget.file != old.file) _showHunk();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int get _hunkRow {
    var n = -1;
    for (final (i, r) in widget.rows.indexed) {
      if (r is HunkRow && ++n == widget.view.hunk) return i;
    }
    return -1;
  }

  void _showHunk() {
    final row = _hunkRow;
    if (row < 0 || !_scroll.hasClients) return;
    final ctx = _hunkKey.currentContext;
    if (ctx == null) _scroll.jumpTo((row * _approxRow).clamp(0, _scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _hunkKey.currentContext;
      if (c != null) Scrollable.ensureVisible(c, alignment: .1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget, rows = w.rows, file = w.file;
    if (file.binary) return const Empty('Binary file');
    if (rows.isEmpty) return Empty(file.status == 'renamed' ? 'Renamed without changes' : 'No textual changes');
    final current = _hunkRow;
    final list = ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: rows.length,
      itemBuilder: (context, i) => _RowView(key: i == current ? _hunkKey : null, row: rows[i], view: w.view, current: i == current),
    );
    if (w.view.wrap || w.view.sideBySide) return SelectionArea(child: list);
    return SelectionArea(child: _Sideways(longest: _longest(), child: list));
  }

  int _longest() => widget.file.hunks.expand((h) => h.lines).fold(0, (n, l) => math.max(n, _shown(l).length));
}

/// [child] as wide as [longest] characters of code (at least the viewport), scrolled sideways.
class _Sideways extends StatelessWidget {
  const _Sideways({required this.longest, required this.child});

  final int longest;
  final Widget child;

  static double? _cw;
  static double get charWidth => _cw ??= (TextPainter(
    text: const TextSpan(text: 'MMMMMMMMMM', style: T.code),
    textDirection: TextDirection.ltr,
  )..layout()).width / 10;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(c.maxWidth, 44 * 2 + 18 + 16 + longest * charWidth),
          height: c.maxHeight,
          child: child,
        ),
      ),
    ),
  );
}

class _WithSide extends StatelessWidget {
  const _WithSide({required this.body, required this.side});

  final Widget body, side;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: body),
      const VerticalDivider(width: 1),
      SizedBox(width: 320, child: side),
    ],
  );
}

// Molecules -----------------------------------------------------------------------------------------

class _FileTitle extends StatelessWidget {
  const _FileTitle(this.file);

  final DiffFile file;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(statusIcon(file.status), size: 15, color: statusColor(file.status)),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          file.status == 'renamed' ? '${file.oldPath} → ${file.path}' : file.path,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 10),
      Text('+${file.additions}', style: const TextStyle(fontSize: 12, color: C.green)),
      const SizedBox(width: 4),
      Text('−${file.deletions}', style: const TextStyle(fontSize: 12, color: C.red)),
    ],
  );
}

/// Picks the widget for one [DiffRow].
class _RowView extends StatelessWidget {
  const _RowView({super.key, required this.row, required this.view, this.current = false});

  final DiffRow row;
  final DiffView view;

  /// The current hunk's header.
  final bool current;

  @override
  Widget build(BuildContext context) => switch (row) {
    HunkRow(:final hunk) => _HunkHeader(
      hunk: hunk,
      current: current,
      onLine: view.onLine,
      actions: view.hunkActions?.call(hunk) ?? [],
    ),
    LineRow(:final line) => _UnifiedLine(line: line, wrap: view.wrap, onLine: view.onLine),
    PairRow(:final left, :final right) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HalfLine(line: left, old: true, wrap: view.wrap, onLine: view.onLine)),
          const VerticalDivider(width: 1),
          Expanded(child: _HalfLine(line: right, old: false, wrap: view.wrap, onLine: view.onLine)),
        ],
      ),
    ),
  };
}

class _HunkHeader extends StatelessWidget {
  const _HunkHeader({required this.hunk, required this.onLine, required this.actions, this.current = false});

  final Hunk hunk;
  final OnDiffLine? onLine;
  final List<Widget> actions;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final h = hunk;
    return Container(
      color: current ? C.accent.withValues(alpha: .18) : C.surface2,
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onLine == null ? null : () => onLine!(h.firstChangedLine, false),
              child: Text(
                '@@ −${h.oldStart},${h.oldCount} +${h.newStart},${h.newCount} @@ ${h.section}',
                style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.accent),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A unified row: old and new line numbers, sign, text. Clicks open the new side, deletions the old.
class _UnifiedLine extends StatelessWidget {
  const _UnifiedLine({required this.line, required this.wrap, required this.onLine});

  final DiffLine line;
  final bool wrap;
  final OnDiffLine? onLine;

  @override
  Widget build(BuildContext context) {
    final look = lookOf(line.kind);
    final isOld = line.kind == LineKind.del;
    return _CodeLine(
      look: look,
      gutters: ['${line.oldLine ?? ''}', '${line.newLine ?? ''}'],
      text: _shown(line),
      wrap: wrap,
      onTap: _tap(onLine, isOld ? line.oldLine : line.newLine, isOld),
    );
  }
}

/// One side of a side-by-side row; null: blank filler. The left side opens the old file only for
/// deletions; context opens the new side like everywhere else.
class _HalfLine extends StatelessWidget {
  const _HalfLine({required this.line, required this.old, required this.wrap, required this.onLine});

  final DiffLine? line;
  final bool old, wrap;
  final OnDiffLine? onLine;

  @override
  Widget build(BuildContext context) {
    final l = line;
    if (l == null) return Container(color: C.surface.withValues(alpha: .5));
    final kind = l.kind == LineKind.context ? LineKind.context : (old ? LineKind.del : LineKind.add);
    final isOld = old && l.kind == LineKind.del;
    return _CodeLine(
      look: lookOf(kind),
      gutters: ['${(old ? l.oldLine : l.newLine) ?? ''}'],
      text: _shown(l),
      wrap: wrap,
      onTap: _tap(onLine, isOld ? l.oldLine : l.newLine, isOld),
    );
  }
}

VoidCallback? _tap(OnDiffLine? onLine, int? line, bool isOld) =>
    onLine == null || line == null ? null : () => onLine(line, isOld);

// Atoms ---------------------------------------------------------------------------------------------

/// Line number gutters, sign and code text on the line's background; clickable when [onTap] is set.
class _CodeLine extends StatelessWidget {
  const _CodeLine({required this.look, required this.gutters, required this.text, required this.wrap, this.onTap});

  final LineLook look;
  final List<String> gutters;
  final String text;
  final bool wrap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _ClickLine(
    onTap: onTap,
    child: Container(
      color: look.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in gutters) _Gutter(g, look.gutter),
          SizedBox(
            width: 18,
            child: Text(look.sign, textAlign: TextAlign.center, style: T.code.copyWith(color: look.signColor)),
          ),
          Expanded(
            child: Text(
              text,
              style: T.code,
              softWrap: wrap,
              overflow: wrap ? null : TextOverflow.clip,
              maxLines: wrap ? null : 1,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Gutter extends StatelessWidget {
  const _Gutter(this.n, this.bg);

  final String n;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    color: bg,
    padding: const EdgeInsets.only(right: 6),
    child: Text(n, textAlign: TextAlign.right, style: T.code.copyWith(color: C.faint)),
  );
}

/// A diff line: pointer cursor and a faint highlight on hover when clickable.
class _ClickLine extends StatefulWidget {
  const _ClickLine({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_ClickLine> createState() => _ClickLineState();
}

class _ClickLineState extends State<_ClickLine> {
  bool _hover = false;

  void _setHover(bool v) => setState(() => _hover = v);

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          children: [
            widget.child,
            if (_hover) Positioned.fill(child: IgnorePointer(child: Container(color: C.accent.withValues(alpha: .07)))),
          ],
        ),
      ),
    );
  }
}
