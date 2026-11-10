import 'package:flutter/material.dart';

import '../../tasks/model.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_parts.dart';
import 'rich.dart';

/// Identifies a legacy item in the selection.
class LegacyKey {
  const LegacyKey(this.file, this.line);
  final String file;
  final int line;
  @override
  bool operator ==(Object other) => other is LegacyKey && other.file == file && other.line == line;
  @override
  int get hashCode => Object.hash(file, line);
}

/// A bullet of the old notes, read-only, with Promote to task.
class LegacyDetail extends StatelessWidget {
  const LegacyDetail({
    super.key,
    required this.item,
    required this.onClose,
    required this.onPromote,
    required this.onOpen,
    this.promotedAs,
    this.onTask,
  });

  final LegacyItem item;
  final VoidCallback onClose;
  final VoidCallback onPromote;
  final VoidCallback onOpen;

  /// A task whose original notes hold this item already, if any.
  final String? promotedAs;
  final void Function(String id)? onTask;

  @override
  Widget build(BuildContext context) {
    final i = item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(kicker: 'legacy/${i.file}', title: i.text, onClose: onClose),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            children: [
              Prop(
                'State',
                Row(
                  children: [
                    Icon(
                      i.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: 16,
                      color: i.done ? C.accent : C.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(i.done ? 'done' : 'open', style: T.body),
                    if (i.untested) ...[const SizedBox(width: 8), const Pill('untested', color: C.yellow)],
                  ],
                ),
              ),
              Prop('Section', Text(i.section.isEmpty ? '–' : i.section, style: T.body)),
              if (i.commits.isNotEmpty)
                Prop(
                  'Commits',
                  pillRow([
                    for (final c in i.commits)
                      Text(
                        c,
                        style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.muted),
                      ),
                  ]),
                ),
              if (promotedAs != null)
                Prop(
                  'Task',
                  LinkChip(icon: Icons.task_alt, label: promotedAs!, onTap: () => onTask?.call(promotedAs!)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              if (i.notes.isNotEmpty)
                DetailSection(
                  'Notes',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final n in i.notes)
                        Padding(
                          padding: EdgeInsets.only(left: (n.length - n.trimLeft().length) * 5.0, bottom: 4),
                          child: RichLine(
                            n.trim().replaceFirst(RegExp(r'^[-*] (\[[ xX]\] )?'), ''),
                            style: T.body.copyWith(height: 1.4),
                            onTask: onTask,
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
            children: [
              SmallButton('Open in Neovim', icon: Icons.open_in_new, onPressed: onOpen),
              const Spacer(),
              SmallButton(
                promotedAs == null ? 'Promote to task' : 'Promote again',
                icon: Icons.upgrade,
                primary: promotedAs == null,
                onPressed: onPromote,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
