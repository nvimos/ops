import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'rich.dart';

/// Shared pieces of the detail panels.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.kicker,
    required this.title,
    required this.onClose,
    this.actions = const [],
  });

  final String kicker;
  final String title;
  final VoidCallback onClose;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kicker,
                  style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...actions,
              IconButton(
                tooltip: 'Close (Esc)',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: onClose,
                icon: const Icon(Icons.close, color: C.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectionArea(
            child: RichLine(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.3, color: C.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the properties block: label on the left, value on the right.
class Prop extends StatelessWidget {
  const Prop(this.label, this.child, {super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 96, child: Text(label, style: T.small)),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}

/// A titled block of the detail body.
class DetailSection extends StatelessWidget {
  const DetailSection(this.title, this.child, {super.key, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title.toUpperCase(), style: T.section),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// A clickable chip (linked record).
class LinkChip extends StatelessWidget {
  const LinkChip({super.key, required this.icon, required this.label, this.onTap, this.color = C.text});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: C.border),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: C.muted),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress bar with done/total.
class Progress extends StatelessWidget {
  const Progress(this.done, this.total, {super.key, this.width = 60});

  final int done, total;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: done / total,
              backgroundColor: C.border,
              color: done == total ? C.green : C.accent,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('$done/$total', style: T.tiny),
      ],
    );
  }
}

Widget pillRow(List<Widget> children) => Wrap(spacing: 6, runSpacing: 4, children: children);

Widget labelPill(String l) => Pill(l, color: C.muted);
