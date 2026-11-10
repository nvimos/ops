import 'package:flutter/material.dart';

import '../state/session.dart';
import 'connect.dart';
import 'pr_view.dart';
import 'theme.dart';
import 'widgets.dart';

enum Mode { pullRequest, changes, tasks }

/// The window: a narrow mode rail, the mode's content, a status bar.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Mode _mode = Mode.pullRequest;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Scaffold(
      body: Column(children: [
        Expanded(
          child: Row(children: [
            _ModeRail(mode: _mode, onSelect: (m) => setState(() => _mode = m)),
            const VerticalDivider(width: 1),
            Expanded(child: s.conn == Conn.connected ? _content() : const ConnectScreen()),
          ]),
        ),
        const _StatusBar(),
      ]),
    );
  }

  Widget _content() {
    switch (_mode) {
      case Mode.pullRequest:
        return const PrView();
      case Mode.changes:
        return const Empty('Changes: working tree vs HEAD');
      case Mode.tasks:
        return const Empty('Tasks: OpenSpec and Backlog.md');
    }
  }
}

class _ModeRail extends StatelessWidget {
  const _ModeRail({required this.mode, required this.onSelect});

  final Mode mode;
  final ValueChanged<Mode> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget item(Mode m, IconData icon, String tip) {
      final sel = m == mode;
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => onSelect(m),
          child: Container(
            width: 48,
            height: 44,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: sel ? C.accent : Colors.transparent, width: 2)),
            ),
            child: Icon(icon, size: 20, color: sel ? C.text : C.muted),
          ),
        ),
      );
    }

    return Container(
      width: 48,
      color: C.surface,
      child: Column(children: [
        const SizedBox(height: 8),
        item(Mode.pullRequest, Icons.merge_type, 'Pull request'),
        item(Mode.changes, Icons.edit_note, 'Changes'),
        item(Mode.tasks, Icons.view_kanban_outlined, 'Tasks'),
      ]),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  String _short(String path, String? root) {
    var p = path.replaceAll('\\', '/');
    if (root != null && p.toLowerCase().startsWith('${root.toLowerCase()}/')) p = p.substring(root.length + 1);
    return p.isEmpty ? '[No Name]' : p;
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final (color, label) = switch (s.conn) {
      Conn.connected => (C.green, s.address),
      Conn.connecting => (C.yellow, 'connecting to ${s.address}'),
      Conn.disconnected => (C.faint, 'not connected'),
    };
    final cur = s.cursor;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(color: C.surface, border: Border(top: BorderSide(color: C.border))),
      child: Row(children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(label, style: T.tiny),
        if (s.repo?.head != null) ...[
          const SizedBox(width: 14),
          const Icon(Icons.call_split, size: 12, color: C.muted),
          const SizedBox(width: 4),
          Text(s.repo!.head!, style: T.tiny),
        ],
        const Spacer(),
        if (cur != null)
          Text('${_short(cur.name, s.repo?.root)}  ${cur.row}:${cur.col + 1}', style: T.tiny),
      ]),
    );
  }
}
