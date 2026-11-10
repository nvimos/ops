import 'package:flutter/material.dart';

import '../../tasks/model.dart';
import '../../tasks/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'change_detail.dart';
import 'detail_parts.dart';
import 'icons.dart';
import 'rich.dart';

/// Identifies a requirement of the living spec in the selection.
class SpecKey {
  const SpecKey(this.capability, this.requirement);
  final String capability, requirement;
  @override
  bool operator ==(Object other) =>
      other is SpecKey && other.capability == capability && other.requirement == requirement;
  @override
  int get hashCode => Object.hash(capability, requirement);
}

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
  Widget build(BuildContext context) {
    final history = ws.changesTouching(requirement.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(kicker: 'spec ${spec.capability}', title: requirement.name, onClose: onClose),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              if (spec.purpose.isNotEmpty)
                DetailSection(
                  'Purpose of ${spec.capability}',
                  RichLine(spec.purpose, style: T.body.copyWith(height: 1.45)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: RequirementCard(requirement: requirement),
              ),
              DetailSection(
                'Changes that touched this',
                history.isEmpty
                    ? const Text('None recorded.', style: T.small)
                    : Column(
                        children: [
                          for (final (c, d) in history)
                            HoverRow(
                              onTap: () => onChange(c),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                              child: Row(
                                children: [
                                  StatusIcon(c.stage, size: 13),
                                  const SizedBox(width: 8),
                                  Pill(
                                    switch (d.op) {
                                      DeltaOp.added => 'Added',
                                      DeltaOp.modified => 'Modified',
                                      DeltaOp.removed => 'Removed',
                                      DeltaOp.renamed => 'Renamed',
                                    },
                                    color: switch (d.op) {
                                      DeltaOp.added => C.green,
                                      DeltaOp.modified => C.yellow,
                                      DeltaOp.removed => C.red,
                                      DeltaOp.renamed => C.purple,
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: RichLine(c.title, maxLines: 1)),
                                  if (c.archiveDate != null)
                                    Text(
                                      '${c.archiveDate!.year}-${c.archiveDate!.month.toString().padLeft(2, '0')}-${c.archiveDate!.day.toString().padLeft(2, '0')}',
                                      style: T.tiny,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: C.border)),
          ),
          child: Row(
            children: [SmallButton('Open in Neovim', icon: Icons.open_in_new, onPressed: onOpen)],
          ),
        ),
      ],
    );
  }
}
