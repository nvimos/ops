import 'package:flutter/material.dart';

import 'theme.dart';

/// A row that highlights on hover and when selected; the basic list item everywhere.
class HoverRow extends StatefulWidget {
  const HoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsets padding;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected ? C.surface2 : (_hover ? C.hover : Colors.transparent);
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(color: bg, padding: widget.padding, child: widget.child),
      ),
    );
  }
}

/// A small rounded label: status, Added/Modified/Removed, counts.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = C.muted, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: filled ? C.bg : color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// A compact flat button.
class SmallButton extends StatelessWidget {
  const SmallButton(this.label, {super.key, this.onPressed, this.icon, this.primary = false, this.danger = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? C.red : (primary ? C.bg : C.text);
    final bg = primary ? C.accent : C.surface2;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: onPressed == null ? C.surface : bg,
        foregroundColor: fg,
        disabledForegroundColor: C.faint,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: BorderSide(color: primary ? C.accent : C.border),
        ),
        textStyle: const TextStyle(fontSize: 12.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 5)],
          Text(label),
        ],
      ),
    );
  }
}

/// A header bar for a pane.
class PaneHeader extends StatelessWidget {
  const PaneHeader({super.key, required this.title, this.trailing = const []});

  final Widget title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle(style: T.title, overflow: TextOverflow.ellipsis, child: title),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// Centered muted text for empty states.
class Empty extends StatelessWidget {
  const Empty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, style: T.small, textAlign: TextAlign.center),
    ),
  );
}

/// A small progress circle for "loading" and "running".
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(strokeWidth: 1.5),
  );
}
