import 'package:material_ui/material_ui.dart';

import '../state/log_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Log mode: action reports and repository scans, newest first. Each row
/// opens to its full detail; the text is selectable.
class LogView extends StatefulWidget {
  const LogView({super.key, required this.log, this.focusNode});

  final LogState log;
  final FocusNode? focusNode;

  @override
  State<LogView> createState() => LogViewState();
}

class LogViewState extends State<LogView> {
  final Set<int> _open = {};
  int _cursor = 0;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PaneHeader(title: Text('LOG')),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.log,
              builder: (context, _) {
                final entries = widget.log.entries;
                if (entries.isEmpty) {
                  return const Center(child: Text('No actions yet.', style: T.small));
                }
                _cursor = _cursor.clamp(0, entries.length - 1);
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _row(entries[i], i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(LogEntry entry, int index) {
    final open = _open.contains(index);
    return Tooltip(
      message: open ? 'Fold this report' : 'Open the full report',
      child: HoverRow(
        selected: index == _cursor,
        onTap: () => setState(() {
          _cursor = index;
          _open.remove(index) || _open.add(index);
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: 64, child: Text(entry.time, style: T.tiny)),
                Expanded(
                  child: Text(
                    entry.title,
                    style: entry.error
                        ? const TextStyle(fontSize: 12, color: C.red)
                        : T.body,
                  ),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 16, color: C.muted),
              ],
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectionArea(child: Text(entry.detail, style: T.code)),
              ),
          ],
        ),
      ),
    );
  }
}
