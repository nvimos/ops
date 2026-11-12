import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../state/list_pair.dart';
import 'theme.dart';
import 'widgets.dart';

/// Height of a list header ([SectionTitle]).
const sectionHeader = 32.0;

/// How tall a list wants to be: [rows] of [row] px plus [pad] around them.
typedef ListSize = ({int rows, double row, double pad});

/// Heights of the two lists of [pair] in [free] px; null: it takes the rest, 0: folded.
/// The dominant list takes the rest; the other at most 6 rows, or 3 when the dominant one would
/// not fit. A folded list hands the rest to the other one.
List<double?> pairHeights(ListPair pair, double free, List<ListSize> sizes) {
  final h = <double?>[for (final c in pair.collapsed) c ? 0 : null];
  final d = pair.dominant, o = 1 - d;
  if (pair.collapsed[d] || pair.collapsed[o]) return h;
  double rows(ListSize s, int max) => math.min(s.rows, max) * s.row + s.pad;
  final need = rows(sizes[d], 1 << 20);
  h[o] = free - rows(sizes[o], 6) < need ? rows(sizes[o], 3) : rows(sizes[o], 6);
  return h;
}

/// Two lists under their headers, sized by [pairHeights]; [banner] (optional) sits on top.
class ListPairColumn extends StatelessWidget {
  const ListPairColumn({
    super.key,
    required this.pair,
    required this.headers,
    required this.lists,
    required this.sizes,
    this.banner,
  });

  final ListPair pair;
  final List<Widget> headers, lists;
  final List<ListSize> sizes;
  final Widget? banner;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final free = c.maxHeight - 2 * sectionHeader - (banner != null ? sectionHeader : 0);
      final h = pairHeights(pair, free, sizes);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?banner,
          headers[0],
          ?_sized(h[0], lists[0]),
          const Divider(height: 1),
          headers[1],
          ?_sized(h[1], lists[1]),
          if (h[0] == 0 && h[1] == 0) const Spacer(),
        ],
      );
    },
  );

  static Widget? _sized(double? height, Widget child) => switch (height) {
    null => Expanded(child: child),
    0 => null,
    _ => SizedBox(height: height, child: child),
  };
}

/// A list header: chevron, title, count, extra text, spinner, actions. A click folds the list.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.count,
    required this.collapsed,
    required this.onTap,
    this.extra,
    this.loading = false,
    this.actions = const [],
    this.active = false,
  });

  /// The keys act on this list (Tab moves between them).
  final bool active;

  final String title, count;
  final String? extra;
  final bool loading;
  final List<Widget> actions;
  final VoidCallback onTap;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 14, color: C.muted),
        Text(title, style: active ? T.section.copyWith(color: C.accent) : T.section),
        const SizedBox(width: 6),
        Text(count, style: T.tiny),
        const Spacer(),
        if (extra != null) Text(extra!, style: T.tiny),
        if (loading) const _Spinner(),
        ...actions,
      ],
    );
    return SizedBox(
      height: sectionHeader,
      child: HoverRow(onTap: onTap, padding: const EdgeInsets.fromLTRB(12, 0, 6, 0), child: row),
    );
  }
}

/// The header button that expands or collapses every folder of a file tree (zR / zM).
class FoldAllButton extends StatelessWidget {
  const FoldAllButton({super.key, required this.folded, required this.onTap});

  /// Some folder is folded: the button expands all.
  final bool folded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconToggle(
    icon: folded ? Icons.unfold_more : Icons.unfold_less,
    tip: folded ? 'Expand all folders (zR)' : 'Collapse all folders (zM)',
    onTap: onTap,
  );
}

/// The header button that gives this list the most room; lit while it has it.
class DominantButton extends StatelessWidget {
  const DominantButton({super.key, required this.what, required this.on, required this.onTap});

  /// "files", "commits": the tooltip says what gets the room.
  final String what;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      IconToggle(icon: Icons.open_in_full, tip: 'Give the $what the most room', on: on, onTap: onTap);
}

/// A small icon button that shows whether its option is on.
class IconToggle extends StatelessWidget {
  const IconToggle({super.key, required this.icon, required this.tip, required this.onTap, this.on = false});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool on;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(4),
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: on ? C.accent.withValues(alpha: .15) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 14, color: on ? C.accent : C.muted),
      ),
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 6),
    child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
  );
}
