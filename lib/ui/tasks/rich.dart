import 'package:flutter/gestures.dart';
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
  final void Function(Check c)? onCheck;

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
                onTap: onCheck == null ? null : () => onCheck!(check),
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

/// A checklist item: a box you can click, the text without `- [ ]`.
class CheckRow extends StatelessWidget {
  const CheckRow(this.check, {super.key, this.onTap, this.onTask});

  final Check check;
  final VoidCallback? onTap;
  final void Function(String id)? onTask;

  @override
  Widget build(BuildContext context) {
    final text = check.text.replaceFirst(RegExp(r'^#\d+\s+'), '').replaceFirst(RegExp(r'^\d+(\.\d+)*\s+'), '');
    return Padding(
      padding: EdgeInsets.only(left: check.indent * 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 8, 0),
              child: Icon(
                check.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 17,
                color: check.done ? C.accent : C.muted,
              ),
            ),
          ),
          Expanded(
            child: RichLine(
              text,
              onTask: onTask,
              style: T.body.copyWith(height: 1.45, color: check.done ? C.muted : C.text),
            ),
          ),
        ],
      ),
    );
  }
}
