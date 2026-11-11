import 'package:flutter/material.dart';

import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'change_detail.dart';
import 'detail_parts.dart';
import 'rich.dart';

/// A requirement of the living spec, and every change that ever touched it.
class SpecDetail extends StatelessWidget {
  const SpecDetail({
    super.key,
    required this.spec,
    required this.requirement,
    required this.ws,
    required this.onClose,
    required this.onChange,
    required this.onOpen,
  });

  final Spec spec;
  final Requirement requirement;
  final Workspace ws;
  final VoidCallback onClose;
  final void Function(Change c) onChange;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PanelHeader(kicker: 'spec ${spec.capability}', title: requirement.name, onClose: onClose),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            if (spec.purpose.isNotEmpty)
              DetailSection('Purpose of ${spec.capability}', RichLine(spec.purpose, style: T.body.copyWith(height: 1.45))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: RequirementCard(requirement: requirement),
            ),
            DetailSection('Changes that touched this', _History(ws.changesTouching(requirement.name), onChange: onChange)),
          ],
        ),
      ),
      PanelFooter(children: [SmallButton('Open in Neovim', icon: Icons.open_in_new, onPressed: onOpen)]),
    ],
  );
}

class _History extends StatelessWidget {
  const _History(this.history, {required this.onChange});

  final List<(Change, Delta)> history;
  final void Function(Change c) onChange;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const Text('None recorded.', style: T.small);
    return Column(
      children: [
        for (final (c, d) in history) ChangeLine(change: c, op: d.op, indent: 4, onTap: () => onChange(c)),
      ],
    );
  }
}
