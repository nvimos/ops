import 'package:material_ui/material_ui.dart';

import '../../tasks/model.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_parts.dart';
import 'rich.dart';

/// A bullet of the old notes, read-only, with Promote to task.
class LegacyDetail extends StatelessWidget {
  const LegacyDetail({
    super.key,
    required this.item,
    required this.onClose,
    this.widen,
    required this.onPromote,
    required this.onOpen,
    this.promotedAs,
    this.onTask,
  });

  final LegacyItem item;
  final VoidCallback onClose;
  final PanelWiden? widen;
  final VoidCallback onPromote;
  final VoidCallback onOpen;

  /// A task whose original notes hold this item already, if any.
  final String? promotedAs;
  final void Function(String id)? onTask;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PanelHeader(kicker: 'legacy/${item.file}', title: item.text, onClose: onClose, widen: widen),
      _LegacyProps(item: item, promotedAs: promotedAs, onTask: onTask),
      const Divider(height: 1),
      Expanded(
        child: ListView(
          children: [if (item.notes.isNotEmpty) DetailSection('Notes', _Notes(item.notes, onTask: onTask))],
        ),
      ),
      PanelFooter(
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
    ],
  );
}

class _LegacyProps extends StatelessWidget {
  const _LegacyProps({required this.item, required this.promotedAs, required this.onTask});

  final LegacyItem item;
  final String? promotedAs;
  final void Function(String id)? onTask;

  @override
  Widget build(BuildContext context) {
    final i = item, p = promotedAs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: [
          Prop('State', _State(done: i.done, untested: i.untested)),
          Prop('Section', Text(i.section.isEmpty ? '–' : i.section, style: T.body)),
          if (i.commits.isNotEmpty) Prop('Commits', pillRow([for (final c in i.commits) _Sha(c)])),
          if (p != null) Prop('Task', LinkChip(icon: Icons.task_alt, label: p, onTap: () => onTask?.call(p))),
        ],
      ),
    );
  }
}

class _State extends StatelessWidget {
  const _State({required this.done, required this.untested});

  final bool done, untested;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        size: 16,
        color: done ? C.accent : C.muted,
      ),
      const SizedBox(width: 6),
      Text(done ? 'done' : 'open', style: T.body),
      if (untested) ...[const SizedBox(width: 8), const Pill('untested', color: C.yellow)],
    ],
  );
}

class _Sha extends StatelessWidget {
  const _Sha(this.sha);

  final String sha;

  @override
  Widget build(BuildContext context) =>
      Text(sha, style: const TextStyle(fontSize: 12, fontFamily: mono, color: C.muted));
}

/// The item's sub-bullets, indented as in the file, without their list markers.
class _Notes extends StatelessWidget {
  const _Notes(this.notes, {required this.onTask});

  final List<String> notes;
  final void Function(String id)? onTask;

  static double indentOf(String n) => (n.length - n.trimLeft().length) * 5.0;

  static String textOf(String n) => n.trim().replaceFirst(RegExp(r'^[-*] (\[[ xX]\] )?'), '');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final n in notes)
        Padding(
          padding: EdgeInsets.only(left: indentOf(n), bottom: 4),
          child: RichLine(textOf(n), style: T.body.copyWith(height: 1.4), onTask: onTask),
        ),
    ],
  );
}
