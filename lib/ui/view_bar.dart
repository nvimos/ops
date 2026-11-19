import 'package:material_ui/material_ui.dart';

import '../state/diff_prefs.dart';
import 'theme.dart';

/// The bar above the panes of Pull request and Changes: one button for each way to show the diff,
/// Unified, Split (side by side) and Merge. Z steps through them; v toggles Unified and Split. Merge
/// is for a merge with conflicts: without one its button is dimmed and does nothing.
class ViewBar extends StatelessWidget {
  const ViewBar({super.key, required this.layout, required this.mergeOpen, required this.onLayout});

  final DiffLayout layout;

  /// A merge with conflicts is open, so the Merge view has something to show.
  final bool mergeOpen;
  final ValueChanged<DiffLayout> onLayout;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: C.surface,
      border: Border(bottom: BorderSide(color: C.border)),
    ),
    child: Row(
      children: [
        _ViewButton(
          icon: Icons.subject,
          label: 'Unified',
          tip: 'Unified diff (v toggles with Split, Z steps through the views)',
          selected: layout == DiffLayout.unified,
          onTap: () => onLayout(DiffLayout.unified),
        ),
        const SizedBox(width: 4),
        _ViewButton(
          icon: Icons.compare,
          label: 'Split',
          tip: 'Side by side: old and new next to each other (v, Z)',
          selected: layout == DiffLayout.sideBySide,
          onTap: () => onLayout(DiffLayout.sideBySide),
        ),
        const SizedBox(width: 4),
        _ViewButton(
          icon: Icons.call_merge,
          label: 'Merge',
          tip: mergeOpen || layout == DiffLayout.conflict
              ? 'The merge with its conflicts (Z)'
              : 'Merge: only while a merge has conflicts',
          selected: layout == DiffLayout.conflict,
          enabled: mergeOpen || layout == DiffLayout.conflict,
          onTap: () => onLayout(DiffLayout.conflict),
        ),
      ],
    ),
  );
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.icon,
    required this.label,
    required this.tip,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label, tip;
  final bool selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled ? C.faint : (selected ? C.text : C.muted);
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: enabled ? onTap : null,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? C.surface2 : null,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: selected ? C.accent : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(label, style: T.small.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
