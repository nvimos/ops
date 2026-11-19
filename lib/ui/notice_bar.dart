import 'package:material_ui/material_ui.dart';

import '../state/notices.dart';
import 'error_view.dart';
import 'theme.dart';
import 'widgets.dart';

/// The bar above the status bar that tells what an action did wrong, in every mode. It stays while the
/// mouse is over it, goes on its own afterwards, has the full text behind Details, and counts a
/// message that repeats. [Notices] decides what is shown and for how long.
class NoticeBar extends StatelessWidget {
  const NoticeBar({super.key, required this.notices});

  final Notices notices;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notices,
    builder: (context, _) {
      final n = notices.current;
      if (n == null) return const SizedBox.shrink();
      return MouseRegion(
        onEnter: (_) => notices.setHovered(true),
        onExit: (_) => notices.setHovered(false),
        child: _Bar(notice: n, onDetails: () => showErrorDetails(context, n.detail!), onClose: notices.dismiss),
      );
    },
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.notice, required this.onDetails, required this.onClose});

  final Notice notice;
  final VoidCallback onDetails, onClose;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: const BoxDecoration(
      color: C.surface2,
      border: Border(top: BorderSide(color: C.border)),
    ),
    child: Row(
      children: [
        Icon(notice.failure ? Icons.error_outline : Icons.info_outline, size: 15, color: notice.failure ? C.yellow : C.muted),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(notice.message, style: T.body, maxLines: 2)),
        if (notice.count > 1) Padding(padding: const EdgeInsets.only(left: 8), child: Pill('×${notice.count}')),
        if (notice.hasDetail) ...[
          const SizedBox(width: 8),
          Tooltip(message: 'The full text, with the trace', child: SmallButton('Details', onPressed: onDetails)),
        ],
        const SizedBox(width: 4),
        IconAction(icon: Icons.close, tooltip: 'Dismiss', onPressed: onClose),
      ],
    ),
  );
}
