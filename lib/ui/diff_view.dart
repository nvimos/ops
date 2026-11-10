import 'package:flutter/material.dart';

import '../backend/models.dart';
import 'file_tree.dart';
import 'theme.dart';
import 'widgets.dart';

/// A unified diff of one file: hunk headers, old/new line numbers, colored lines. Clicking a line
/// calls [onLine] with its line number (old side for deletions); [hunkActions] adds buttons to a
/// hunk header (stage, discard, ...).
class DiffView extends StatelessWidget {
  const DiffView({
    super.key,
    required this.file,
    this.onLine,
    this.hunkActions,
    this.headerActions = const [],
    this.side,
  });

  final DiffFile file;
  final void Function(int line, bool isOld)? onLine;
  final List<Widget> Function(Hunk hunk)? hunkActions;
  final List<Widget> headerActions;

  /// Shown at the right of the diff (e.g. a task's Verify list next to a review).
  final Widget? side;

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[];
    for (final h in file.hunks) {
      rows.add(_Row.hunk(h));
      for (final l in h.lines) {
        rows.add(_Row.line(l));
      }
    }
    final title = file.status == 'renamed' ? '${file.oldPath} → ${file.path}' : file.path;
    final body = file.binary
        ? const Empty('Binary file')
        : rows.isEmpty
            ? Empty(file.status == 'renamed' ? 'Renamed without changes' : 'No textual changes')
            : SelectionArea(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 40),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => rows[i].build(this),
                ),
              );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaneHeader(
        title: Row(children: [
          Icon(statusIcon(file.status), size: 15, color: statusColor(file.status)),
          const SizedBox(width: 8),
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 10),
          Text('+${file.additions}', style: const TextStyle(fontSize: 12, color: C.green)),
          const SizedBox(width: 4),
          Text('−${file.deletions}', style: const TextStyle(fontSize: 12, color: C.red)),
        ]),
        trailing: headerActions,
      ),
      Expanded(
        child: side == null
            ? body
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: body),
                const VerticalDivider(width: 1),
                SizedBox(width: 320, child: side),
              ]),
      ),
    ]);
  }
}

class _Row {
  _Row.hunk(Hunk this.hunk) : line = null;
  _Row.line(DiffLine this.line) : hunk = null;

  final Hunk? hunk;
  final DiffLine? line;

  Widget build(DiffView v) {
    final h = hunk;
    if (h != null) {
      return Container(
        color: C.surface2,
        padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
        child: Row(children: [
          Expanded(
            child: InkWell(
              onTap: v.onLine == null ? null : () => v.onLine!(h.firstChangedLine, false),
              child: Text(
                '@@ −${h.oldStart},${h.oldCount} +${h.newStart},${h.newCount} @@ ${h.section}',
                style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.accent),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (v.hunkActions != null) ...v.hunkActions!(h),
        ]),
      );
    }
    final l = line!;
    final (bg, gutter, sign, signColor) = switch (l.kind) {
      LineKind.add => (C.addBg, C.addGutter, '+', C.green),
      LineKind.del => (C.delBg, C.delGutter, '−', C.red),
      LineKind.context => (Colors.transparent, Colors.transparent, ' ', C.faint),
    };
    final target = l.kind == LineKind.del ? l.oldLine : l.newLine;
    return _ClickLine(
      onTap: v.onLine == null || target == null ? null : () => v.onLine!(target, l.kind == LineKind.del),
      child: Container(
        color: bg,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _gutter('${l.oldLine ?? ''}', gutter),
          _gutter('${l.newLine ?? ''}', gutter),
          SizedBox(width: 18, child: Text(sign, textAlign: TextAlign.center, style: T.code.copyWith(color: signColor))),
          Expanded(
            child: Text(
              l.text.replaceAll('\t', '    ') + (l.noEol ? '  ⏎̸' : ''),
              style: T.code,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _gutter(String n, Color bg) => Container(
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

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(children: [
          widget.child,
          if (_hover) Positioned.fill(child: IgnorePointer(child: Container(color: C.accent.withValues(alpha: .07)))),
        ]),
      ),
    );
  }
}
