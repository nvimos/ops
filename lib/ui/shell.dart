import 'package:flutter/material.dart';

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
    return Scaffold(
      body: Column(children: [
        Expanded(
          child: Row(children: [
            _ModeRail(mode: _mode, onSelect: (m) => setState(() => _mode = m)),
            const VerticalDivider(width: 1),
            Expanded(child: _content()),
          ]),
        ),
        const _StatusBar(),
      ]),
    );
  }

  Widget _content() {
    switch (_mode) {
      case Mode.pullRequest:
        return const Empty('Pull request: pick two branches');
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(color: C.surface, border: Border(top: BorderSide(color: C.border))),
      child: const Row(children: [
        Icon(Icons.circle, size: 8, color: C.faint),
        SizedBox(width: 6),
        Text('not connected', style: T.tiny),
      ]),
    );
  }
}
