import 'package:flutter/material.dart';

import '../../tasks/markdown.dart';
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

/// The panel header's "open the file in Neovim" button.
class OpenInNeovimButton extends StatelessWidget {
  const OpenInNeovimButton({super.key, required this.onTap, this.tip = 'Open the file in Neovim (o)'});

  final VoidCallback onTap;
  final String tip;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    iconSize: 17,
    onPressed: onTap,
    icon: const Icon(Icons.open_in_new, color: C.muted),
  );
}

/// Accent text that acts like a link.
class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Text(text, style: const TextStyle(fontSize: 12, color: C.accent), overflow: TextOverflow.ellipsis),
  );
}

/// A titled checklist with its progress; a click on an item toggles it.
class ChecksSection extends StatelessWidget {
  const ChecksSection({super.key, required this.title, required this.checks, required this.onCheck, this.onTask});

  final String title;
  final List<Check> checks;
  final ValueChanged<Check> onCheck;
  final ValueChanged<String>? onTask;

  @override
  Widget build(BuildContext context) => DetailSection(
    title,
    Column(
      children: [
        for (final c in checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: CheckRow(c, onTap: () => onCheck(c), onTask: onTask),
          ),
      ],
    ),
    trailing: Progress(checks.where((c) => c.done).length, checks.length),
  );
}

/// A value with its icon that opens a menu of the other values.
class ChoiceMenu extends StatelessWidget {
  const ChoiceMenu({
    super.key,
    required this.value,
    required this.options,
    required this.icon,
    required this.label,
    required this.tip,
    required this.onPick,
  });

  final String value;
  final List<String> options;
  final Widget Function(String) icon;
  final String Function(String) label;
  final String tip;
  final ValueChanged<String> onPick;

  Widget _entry(String v, TextStyle style) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [icon(v), const SizedBox(width: 8), Text(label(v), style: style)],
  );

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tip,
    color: C.surface2,
    onSelected: onPick,
    itemBuilder: (_) => [for (final v in options) PopupMenuItem(value: v, height: 32, child: _entry(v, T.body))],
    child: _entry(value, T.body),
  );
}

/// The bar of buttons at the bottom of a detail panel.
class PanelFooter extends StatelessWidget {
  const PanelFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border))),
    child: Row(children: children),
  );
}
