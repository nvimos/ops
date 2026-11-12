import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../tasks/markdown.dart';
import '../theme.dart';

/// Inline Markdown to styled spans, with no syntax left: `code`, **bold**, *em*, [text](url),
/// and TASK-n references (clickable when [onTask] is set).
List<InlineSpan> inlineSpans(String text, {TextStyle base = T.body, void Function(String id)? onTask}) {
  final out = <InlineSpan>[];
  final re = RegExp(
    r'`([^`]+)`|\*\*([^*]+)\*\*|(?<![\w*])\*([^*\s][^*]*)\*(?!\w)|\[([^\]]+)\]\(([^)]+)\)|\b(TASK-\d+)\b',
    caseSensitive: false,
  );
  var pos = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > pos) out.add(TextSpan(text: text.substring(pos, m.start)));
    if (m.group(1) != null) {
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(3)),
            child: Text(
              m.group(1)!,
              style: base.copyWith(fontFamily: mono, fontSize: (base.fontSize ?? 13) - 1),
            ),
          ),
        ),
      );
    } else if (m.group(2) != null) {
      out.add(
        TextSpan(
          text: m.group(2),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    } else if (m.group(3) != null) {
      out.add(
        TextSpan(
          text: m.group(3),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    } else if (m.group(4) != null) {
      out.add(
        TextSpan(
          text: m.group(4),
          style: const TextStyle(color: C.accent),
        ),
      );
    } else if (m.group(6) != null) {
      final id = m.group(6)!.toUpperCase();
      out.add(
        TextSpan(
          text: id,
          style: const TextStyle(color: C.accent),
          recognizer: onTask == null ? null : (TapGestureRecognizer()..onTap = () => onTask(id)),
        ),
      );
    }
    pos = m.end;
  }
  if (pos < text.length) out.add(TextSpan(text: text.substring(pos)));
  return out;
}

class RichLine extends StatelessWidget {
  const RichLine(this.text, {super.key, this.style = T.body, this.onTask, this.maxLines});

  final String text;
  final TextStyle style;
  final void Function(String id)? onTask;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: style,
      children: inlineSpans(text, base: style, onTask: onTask),
    ),
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
  );
}

/// Section body blocks as typed widgets: paragraphs, bullets, checks, code, sub-headings.
class Blocks extends StatelessWidget {
  const Blocks(this.blocks, {super.key, this.onTask, this.onCheck});

  final List<Block> blocks;
  final void Function(String id)? onTask;
  final void Function(Check c, bool cycle)? onCheck;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: switch (b) {
              Para(:final text) => RichLine(text, onTask: onTask, style: T.body.copyWith(height: 1.45)),
              Bullet(:final text, :final indent) => Padding(
                padding: EdgeInsets.only(left: indent * 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(2, 7, 8, 0),
                      child: Icon(Icons.circle, size: 4, color: C.muted),
                    ),
                    Expanded(
                      child: RichLine(text, onTask: onTask, style: T.body.copyWith(height: 1.45)),
                    ),
                  ],
                ),
              ),
              CheckBlock(:final check) => CheckRow(
                check,
                onCheck: onCheck == null ? null : (cycle) => onCheck!(check, cycle),
                onTask: onTask,
              ),
              CodeBlock(:final lines) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(4)),
                child: Text(lines.join('\n'), style: T.code.copyWith(fontSize: 12)),
              ),
              SubHeading(:final text) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: RichLine(text, style: T.title.copyWith(fontSize: 13)),
              ),
            },
          ),
      ],
    );
  }
}

/// A checklist item: a box, the text without `- [ ]`. A click on the box or the text ticks it
/// (or clears it), Ctrl+click or right click steps it round the marks (see `nextMark`).
/// [onCheck] gets whether to cycle.
class CheckRow extends StatefulWidget {
  const CheckRow(this.check, {super.key, this.onCheck, this.onTask});

  final Check check;
  final void Function(bool cycle)? onCheck;
  final void Function(String id)? onTask;

  @override
  State<CheckRow> createState() => _CheckRowState();
}

class _CheckRowState extends State<CheckRow> {
  bool _hover = false;

  void _enter(bool on) {
    if (widget.onCheck != null) setState(() => _hover = on);
  }

  @override
  Widget build(BuildContext context) {
    final check = widget.check;
    final onCheck = widget.onCheck;
    final text = check.text.replaceFirst(RegExp(r'^#\d+\s+'), '').replaceFirst(RegExp(r'^\d+(\.\d+)*\s+'), '');
    final muted = check.done || check.mark == 'n';
    return MouseRegion(
      cursor: onCheck == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => _enter(true),
      onExit: (_) => _enter(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCheck == null ? null : () => onCheck(HardwareKeyboard.instance.isControlPressed),
        onSecondaryTap: onCheck == null ? null : () => onCheck(true),
        child: Container(
          decoration: BoxDecoration(color: _hover ? C.hover : Colors.transparent, borderRadius: BorderRadius.circular(4)),
          padding: EdgeInsets.only(left: check.indent * 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(2, 2, 8, 0), child: CheckMark(check.mark)),
              Expanded(
                child: RichLine(
                  text,
                  onTask: widget.onTask,
                  style: T.body.copyWith(height: 1.45, color: muted ? C.muted : C.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The box for a checklist [mark]: blank open, x ticked, `.` in progress (a dot in the box), `~`
/// partly done (a dash), `n` will not do (a cross, dimmed).
class CheckMark extends StatelessWidget {
  const CheckMark(this.mark, {super.key, this.size = 17});

  final String mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return switch (mark) {
      'x' || 'X' => Icon(Icons.check_box_rounded, size: size, color: C.accent),
      '~' => Icon(Icons.indeterminate_check_box_rounded, size: size, color: C.yellow),
      'n' => Icon(Icons.disabled_by_default_rounded, size: size, color: C.faint),
      '.' => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.check_box_outline_blank_rounded, size: size, color: C.accent),
            Container(
              width: size * .3,
              height: size * .3,
              decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
      _ => Icon(Icons.check_box_outline_blank_rounded, size: size, color: C.muted),
    };
  }
}
