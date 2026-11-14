import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../backend/models.dart';
import 'file_tree.dart';
import 'syntax.dart';
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
    this.hunkHeaders = true,
    this.onSign,
    this.signTip = 'Stage hunk',
    this.hunk = -1,
    this.scroll,
  });

  /// A click on the `+` / `−` of a changed block acts on its hunk (stage it, in Changes), like the
  /// hunk header's own button; [signTip] is the tooltip. Null: the sign is plain text.
  final void Function(Hunk hunk)? onSign;
  final String signTip;

  /// Show the header above each hunk; off: its row takes no room, so the code runs on.
  final bool hunkHeaders;

  final DiffFile file;

  /// The scroll position, when the caller moves it (arrow keys); else the view keeps its own.
  final ScrollController? scroll;
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
  LineRow(this.line, this.hunk);
  final DiffLine line;
  final Hunk hunk;
}

class PairRow extends DiffRow {
  PairRow(this.left, this.right, this.hunk);
  final DiffLine? left, right;
  final Hunk hunk;
}

/// The rows to show for [file]. Side by side: context on both sides; each run of deletions paired
/// with the run of additions after it.
List<DiffRow> diffRows(DiffFile file, {required bool sideBySide}) => [
  for (final h in file.hunks) ...[
    HunkRow(h),
    if (sideBySide) ..._pairs(h) else ...[for (final l in h.lines) LineRow(l, h)],
  ],
];

List<DiffRow> _pairs(Hunk hunk) {
  final lines = hunk.lines;
  final out = <DiffRow>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].kind == LineKind.context) {
      out.add(PairRow(lines[i], lines[i], hunk));
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
      out.add(PairRow(k < dels.length ? dels[k] : null, k < adds.length ? adds[k] : null, hunk));
    }
  }
  return out;
}

String _shown(DiffLine l) => l.text.replaceAll('\t', '    ') + (l.noEol ? '  ⏎̸' : '');

/// Colors and sign of a line kind.
typedef LineLook = ({Color bg, String sign, Color signColor});

LineLook lookOf(LineKind k) => switch (k) {
  LineKind.add => (bg: C.addBg, sign: '+', signColor: C.addSign),
  LineKind.del => (bg: C.delBg, sign: '−', signColor: C.red),
  LineKind.context => (bg: Colors.transparent, sign: ' ', signColor: C.faint),
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
  final _own = ScrollController();
  ScrollController get _scroll => widget.view.scroll ?? _own;
  final _hunkKey = GlobalKey();
  late DiffSyntax _syntax = DiffSyntax(widget.file);

  /// A rough row height, to bring a far hunk near before it is built and can be scrolled exactly.
  static const _approxRow = 18.0;

  @override
  void didUpdateWidget(_DiffBody old) {
    super.didUpdateWidget(old);
    if (widget.file != old.file) _syntax = DiffSyntax(widget.file);
    if (widget.view.hunk != old.view.hunk || widget.file != old.file) _showHunk();
    if (widget.file != old.file && widget.view.hunk < 0 && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _own.dispose();
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
      itemBuilder: (context, i) => _RowView(
        key: i == current ? _hunkKey : null,
        row: rows[i],
        view: w.view,
        syntax: _syntax,
        current: i == current,
        before: i > 0 ? rows[i - 1] : null,
        after: i + 1 < rows.length ? rows[i + 1] : null,
      ),
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
      StatusMark(file.status, size: 15),
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
  const _RowView({
    super.key,
    required this.row,
    required this.view,
    required this.syntax,
    this.current = false,
    this.before,
    this.after,
  });

  final DiffRow row;
  final DiffView view;
  final DiffSyntax syntax;

  /// The rows around this one: a run of changed lines of one kind is drawn as one blob.
  final DiffRow? before, after;

  /// Which edges of this row's color fade out: the first line of a run fades at the top, the last
  /// at the bottom, the lines between stay solid.
  Fade _fadeOf(bool old) {
    final k = _kindAt(row, old);
    final up = _kindAt(before, old), down = _kindAt(after, old);
    return (top: up != k, bottom: down != k, above: _changeColor(up, k), below: _changeColor(down, k));
  }

  /// What a click on the sign of a block in [hunk] does; null when the view has no such action.
  SignAction? _signOf(Hunk hunk) {
    final act = view.onSign;
    return act == null ? null : (tip: view.signTip, onTap: () => act(hunk));
  }

  /// The current hunk's header.
  final bool current;

  @override
  Widget build(BuildContext context) => switch (row) {
    HunkRow() when !view.hunkHeaders => const SizedBox.shrink(),
    HunkRow(:final hunk) => _HunkHeader(
      hunk: hunk,
      current: current,
      onLine: view.onLine,
      actions: view.hunkActions?.call(hunk) ?? [],
    ),
    LineRow(:final line, :final hunk) => _UnifiedLine(
      line: line,
      syntax: syntax,
      fade: _fadeOf(true),
      sign: _signOf(hunk),
      wrap: view.wrap,
      onLine: view.onLine,
    ),
    PairRow(:final left, :final right, :final hunk) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HalfLine(line: left, old: true, syntax: syntax, fade: _fadeOf(true), sign: _signOf(hunk), wrap: view.wrap, onLine: view.onLine)),
          const VerticalDivider(width: 1),
          Expanded(child: _HalfLine(line: right, old: false, syntax: syntax, fade: _fadeOf(false), sign: _signOf(hunk), wrap: view.wrap, onLine: view.onLine)),
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
    final tint = current ? C.accent.withValues(alpha: .16) : C.surface2.withValues(alpha: .6);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [tint, tint.withValues(alpha: 0)], stops: const [0, 0.85]),
        border: Border(left: BorderSide(color: current ? C.accent : C.border, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onLine == null ? null : () => onLine!(h.firstChangedLine, false),
              child: _HunkTitle(h),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// "Lines 120–134  +6 −2  in section": where the hunk is, how much it changes, what it is in.
class _HunkTitle extends StatelessWidget {
  const _HunkTitle(this.hunk);

  final Hunk hunk;

  String get _range {
    final h = hunk;
    if (h.newCount == 0) return 'after line ${h.newStart}';
    return h.newCount == 1 ? 'Line ${h.newStart}' : 'Lines ${h.newStart}–${h.newStart + h.newCount - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final added = hunk.lines.where((l) => l.kind == LineKind.add).length;
    final removed = hunk.lines.where((l) => l.kind == LineKind.del).length;
    const small = TextStyle(fontSize: 12, fontFamily: mono);
    return Text.rich(
      TextSpan(
        style: small,
        children: [
          TextSpan(text: _range, style: small.copyWith(color: C.muted)),
          if (added > 0) TextSpan(text: '   +$added', style: small.copyWith(color: C.accent.withValues(alpha: .6))),
          if (removed > 0) TextSpan(text: '  −$removed', style: small.copyWith(color: C.accent.withValues(alpha: .6))),
          if (hunk.section.isNotEmpty) ...[
            TextSpan(text: '   in ', style: small.copyWith(color: C.faint)),
            TextSpan(text: hunk.section, style: small.copyWith(color: C.faint)),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A unified row: old and new line numbers, sign, text. Clicks open the new side, deletions the old.
class _UnifiedLine extends StatelessWidget {
  const _UnifiedLine({required this.line, required this.syntax, required this.fade, required this.sign, required this.wrap, required this.onLine});

  final DiffLine line;
  final DiffSyntax syntax;
  final Fade fade;
  final SignAction? sign;
  final bool wrap;
  final OnDiffLine? onLine;

  @override
  Widget build(BuildContext context) {
    final look = lookOf(line.kind);
    final isOld = line.kind == LineKind.del;
    return _CodeLine(
      look: look,
      fade: fade,
      sign: sign,
      gutters: ['${line.oldLine ?? ''}', '${line.newLine ?? ''}'],
      text: _shown(line),
      span: syntax.spanOf(line),
      wrap: wrap,
      onTap: _tap(onLine, isOld ? line.oldLine : line.newLine, isOld),
    );
  }
}

/// One side of a side-by-side row; null: blank filler. The left side opens the old file only for
/// deletions; context opens the new side like everywhere else.
class _HalfLine extends StatelessWidget {
  const _HalfLine({required this.line, required this.old, required this.syntax, required this.fade, required this.sign, required this.wrap, required this.onLine});

  final DiffLine? line;
  final DiffSyntax syntax;
  final Fade fade;
  final SignAction? sign;
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
      fade: fade,
      sign: sign,
      gutters: ['${(old ? l.oldLine : l.newLine) ?? ''}'],
      text: _shown(l),
      span: syntax.spanOf(l),
      wrap: wrap,
      onTap: _tap(onLine, isOld ? l.oldLine : l.newLine, isOld),
    );
  }
}

VoidCallback? _tap(OnDiffLine? onLine, int? line, bool isOld) =>
    onLine == null || line == null ? null : () => onLine(line, isOld);

// Atoms ---------------------------------------------------------------------------------------------

/// Line number gutters (neutral), then sign and code text on the line's background; clickable when [onTap] is set.
class _CodeLine extends StatelessWidget {
  const _CodeLine({required this.look, required this.fade, this.sign, required this.gutters, required this.text, required this.wrap, this.span, this.onTap});

  final LineLook look;
  final Fade fade;

  /// What a click on the sign does (the first line of a block only); null: nothing.
  final SignAction? sign;
  final List<String> gutters;
  final String text;

  /// The same text with syntax colors; null: [text] plain.
  final TextSpan? span;
  final bool wrap;
  final VoidCallback? onTap;

  Widget _text() {
    final overflow = wrap ? null : TextOverflow.clip;
    final lines = wrap ? null : 1;
    final s = span;
    return s == null
        ? Text(text, style: T.code, softWrap: wrap, overflow: overflow, maxLines: lines)
        : Text.rich(s, style: T.code, softWrap: wrap, overflow: overflow, maxLines: lines);
  }

  @override
  Widget build(BuildContext context) => _ClickLine(
    onTap: onTap,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // the first line of a run has its numbers in the sign's color, the rest stay neutral
        for (final g in gutters) _Gutter(g, fade.top ? look.signColor : C.faint),
        Expanded(child: _changeBox()),
      ],
    ),
  );

  /// The sign and the code on the line's color; the line numbers beside it stay neutral.
  Widget _changeBox() => Stack(
    children: [
      if (look.bg != Colors.transparent) Positioned.fill(child: _Blob(color: look.bg, fade: fade)),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // only the first line of a run carries the sign
          _Sign(fade.top ? look.sign : ' ', color: look.signColor, action: fade.top ? sign : null),
          Expanded(child: _text()),
        ],
      ),
    ],
  );
}

/// The `+` / `−` of a changed block. With an [action] it is a hidden button: it looks like plain
/// text, but shows a pointer and a tooltip, and a click does the action (stages the hunk).
class _Sign extends StatelessWidget {
  const _Sign(this.sign, {required this.color, this.action});

  final String sign;
  final Color color;
  final SignAction? action;

  @override
  Widget build(BuildContext context) {
    final text = SizedBox(
      width: 18,
      child: Text(sign, textAlign: TextAlign.center, style: T.code.copyWith(color: color)),
    );
    final act = action;
    if (act == null || sign.trim().isEmpty) return text;
    // Inside the diff's SelectionArea every Text brings its own I-beam cursor, which beats an outer
    // MouseRegion; a button's text is not selectable, so it has none.
    return Tooltip(
      message: act.tip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: act.onTap,
          child: SelectionContainer.disabled(child: text),
        ),
      ),
    );
  }
}

/// The color behind a changed line: only a soft tint, and it fades out at the left edge and over
/// the right part of the line, so the empty space to the right looks like the background.
class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.fade});

  final Color color;
  final Fade fade;

  static const _sideMask = LinearGradient(
    colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
    stops: [0, 0.04, 0.3, 1],
  );

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: _sideMask.createShader,
    child: DecoratedBox(decoration: _fadeDecoration(color, fade), child: const SizedBox.expand()),
  );
}

/// What a click on the `+` / `−` of a changed block does, and its tooltip.
typedef SignAction = ({String tip, VoidCallback onTap});

/// Which edges of a line's color fade into the background.
/// [above] / [below]: the color of a changed line of the other kind right there, to blend into.
typedef Fade = ({bool top, bool bottom, Color? above, Color? below});

/// The kind of the line a row shows on one side; null for headers and blank filler.
LineKind? _kindAt(DiffRow? r, bool old) => switch (r) {
  LineRow(:final line) => line.kind,
  PairRow(:final left, :final right) => (old ? left : right)?.kind,
  _ => null,
};

/// How strong the color is at its peak (1: the theme's add / delete color as is).
const _tint = 0.6;

/// A run of changed lines is one blob: its color is strongest along the middle of the first line's
/// text (where a strike-through would run), solid through the lines between, and fades into the
/// background at the top edge of the first line and the bottom edge of the last. Where a run meets
/// a run of the other kind (red under green), neither fades out: both end on the same mix of the
/// two colors, so they blend into each other at the line between them.
BoxDecoration _fadeDecoration(Color base, Fade f) {
  final c = base.withValues(alpha: _tint);
  if (!f.top && !f.bottom) return BoxDecoration(color: c);
  Color edge(bool fades, Color? other) => !fades
      ? c
      : other == null
      ? base.withValues(alpha: 0)
      : Color.lerp(c, other.withValues(alpha: _tint), 0.5)!;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [edge(f.top, f.above), c, edge(f.bottom, f.below)],
      stops: const [0, 0.5, 1],
    ),
  );
}

/// The color of a changed line of another kind next to this one; null: no blending there.
Color? _changeColor(LineKind? neighbor, LineKind? own) =>
    neighbor == null || neighbor == own || neighbor == LineKind.context ? null : lookOf(neighbor).bg;

class _Gutter extends StatelessWidget {
  const _Gutter(this.n, this.color);

  final String n;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    padding: const EdgeInsets.only(right: 6),
    child: Text(n, textAlign: TextAlign.right, style: T.code.copyWith(color: color)),
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
