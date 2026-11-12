import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';
import 'icons.dart';

/// The frame every Tasks dialog uses: dark surface, thin border, placed above the middle.
class DialogFrame extends StatelessWidget {
  const DialogFrame({super.key, required this.width, required this.child, this.height, this.top = -.5});

  final double width;
  final double? height;
  final double top;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: C.surface,
    alignment: Alignment(0, top),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: C.border)),
    child: SizedBox(width: width, height: height, child: child),
  );
}

// New task ------------------------------------------------------------------------------------------

class NewTask {
  NewTask(this.title, this.status, this.labels, this.description);
  final String title, status, description;
  final List<String> labels;
}

/// C: a new Backlog.md task. Enter in the title creates it.
class NewTaskDialog extends StatefulWidget {
  const NewTaskDialog({super.key, required this.statuses, this.title = '', this.labels = const []});

  final List<String> statuses;
  final String title;
  final List<String> labels;

  @override
  State<NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends State<NewTaskDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _labels = TextEditingController(text: widget.labels.join(', '));
  final _desc = TextEditingController();
  late String _status = widget.statuses.first;

  @override
  void dispose() {
    _title.dispose();
    _labels.dispose();
    _desc.dispose();
    super.dispose();
  }

  List<String> get _labelList => _labels.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  void _ok() => Navigator.pop(context, NewTask(_title.text, _status, _labelList, _desc.text.trim()));

  void _setStatus(String s) => setState(() => _status = s);

  @override
  Widget build(BuildContext context) => DialogFrame(
    width: 560,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('New task', style: T.small),
          const SizedBox(height: 8),
          _PlainField(controller: _title, hint: 'Title', autofocus: true, big: true, onSubmitted: _ok),
          _PlainField(controller: _desc, hint: 'Description (optional)', lines: 6),
          const SizedBox(height: 10),
          _NewTaskFooter(
            statuses: widget.statuses,
            status: _status,
            onStatus: _setStatus,
            labels: _labels,
            onCreate: _ok,
          ),
        ],
      ),
    ),
  );
}

/// Status picker, labels field and the Create button.
class _NewTaskFooter extends StatelessWidget {
  const _NewTaskFooter({
    required this.statuses,
    required this.status,
    required this.onStatus,
    required this.labels,
    required this.onCreate,
  });

  final List<String> statuses;
  final String status;
  final ValueChanged<String> onStatus;
  final TextEditingController labels;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      StatusPicker(statuses: statuses, value: status, onPick: onStatus),
      const SizedBox(width: 8),
      Expanded(
        child: SizedBox(
          height: 30,
          child: TextField(
            controller: labels,
            style: T.small,
            decoration: const InputDecoration(hintText: 'labels, comma separated'),
          ),
        ),
      ),
      const SizedBox(width: 12),
      SmallButton('Create task', primary: true, onPressed: onCreate),
    ],
  );
}

/// A status as a bordered chip that opens a menu of statuses.
class StatusPicker extends StatelessWidget {
  const StatusPicker({super.key, required this.statuses, required this.value, required this.onPick});

  final List<String> statuses;
  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    color: C.surface2,
    onSelected: onPick,
    itemBuilder: (_) => [
      for (final s in statuses) PopupMenuItem(value: s, height: 32, child: _StatusLabel(s, style: T.body)),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(5)),
      child: _StatusLabel(value, style: T.small),
    ),
  );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel(this.status, {required this.style});

  final String status;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [StatusIcon(status), const SizedBox(width: 8), Text(status, style: style)],
  );
}

/// A borderless text field for titles and descriptions.
class _PlainField extends StatelessWidget {
  const _PlainField({
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.big = false,
    this.lines = 1,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus, big;
  final int lines;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    minLines: lines > 1 ? 2 : 1,
    maxLines: lines,
    style: big ? const TextStyle(fontSize: 16) : T.body,
    decoration: InputDecoration(hintText: hint, filled: false, border: InputBorder.none),
    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
  );
}

// Command palette ----------------------------------------------------------------------------------

class PaletteEntry {
  PaletteEntry(this.label, this.hint, this.icon, this.run);
  final String label, hint;
  final IconData icon;
  final void Function() run;
}

/// Ctrl+K: every action and record, filtered as you type; arrows and Enter.
class Palette extends StatefulWidget {
  const Palette(this.entries, {super.key});

  final List<PaletteEntry> entries;

  @override
  State<Palette> createState() => _PaletteState();
}

class _PaletteState extends State<Palette> {
  static const _rowHeight = 34.0;
  String _q = '';
  int _i = 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<PaletteEntry> get _hits {
    final words = _q.toLowerCase().split(' ').where((w) => w.isNotEmpty);
    return widget.entries
        .where((e) => words.every((w) => '${e.label} ${e.hint}'.toLowerCase().contains(w)))
        .take(200)
        .toList();
  }

  void _query(String v) => setState(() {
    _q = v;
    _i = 0;
  });

  void _go(int d) {
    final n = _hits.length;
    if (n == 0) return;
    setState(() => _i = (_i + d).clamp(0, n - 1));
    if (!_scroll.hasClients) return;
    final top = _i * _rowHeight, view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) _scroll.jumpTo(top);
    if (top + _rowHeight > _scroll.offset + view) _scroll.jumpTo(top + _rowHeight - view);
  }

  void _pick(PaletteEntry e) => Navigator.pop(context, e);

  void _pickCurrent() {
    final hits = _hits;
    if (hits.isNotEmpty) _pick(hits[_i]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final action = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowDown => () => _go(1),
      LogicalKeyboardKey.arrowUp => () => _go(-1),
      LogicalKeyboardKey.enter => _pickCurrent,
      _ => null,
    };
    action?.call();
    return action == null ? KeyEventResult.ignored : KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return DialogFrame(
      width: 620,
      height: 420,
      top: -.6,
      child: Column(
        children: [
          Focus(onKeyEvent: _onKey, child: _PaletteField(onChanged: _query)),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _rowHeight,
              itemCount: hits.length,
              itemBuilder: (_, i) => PaletteRow(entry: hits[i], selected: i == _i, onTap: () => _pick(hits[i])),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteField extends StatefulWidget {
  const _PaletteField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_PaletteField> createState() => _PaletteFieldState();
}

class _PaletteFieldState extends State<_PaletteField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClearOnAltX(
    controller: _text,
    onCleared: widget.onChanged,
    child: TextField(
      controller: _text,
      autofocus: true,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Type a command or search…',
        filled: false,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(16),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ClearButton(controller: _text, onCleared: widget.onChanged),
        ),
        suffixIconConstraints: ClearButton.constraints,
      ),
      onChanged: widget.onChanged,
    ),
  );
}

class PaletteRow extends StatelessWidget {
  const PaletteRow({super.key, required this.entry, required this.selected, required this.onTap});

  final PaletteEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverRow(
    selected: selected,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Icon(entry.icon, size: 15, color: C.muted),
        const SizedBox(width: 10),
        Expanded(child: Text(entry.label, style: T.body, overflow: TextOverflow.ellipsis)),
        Text(entry.hint, style: T.tiny),
      ],
    ),
  );
}

// New change -----------------------------------------------------------------------------------------

/// "New change": one sentence; an agent drafts the proposal, tasks, deltas and the task.
class NewChangeDialog extends StatefulWidget {
  const NewChangeDialog({super.key});

  @override
  State<NewChangeDialog> createState() => _NewChangeDialogState();
}

class _NewChangeDialogState extends State<NewChangeDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _cancel() => Navigator.pop(context);

  void _draft() => Navigator.pop(context, _text.text.trim());

  @override
  Widget build(BuildContext context) => DialogFrame(
    width: 600,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('New change', style: T.small),
          const SizedBox(height: 4),
          const Text(
            'Describe it in a sentence. Claude Code drafts the proposal, tasks, spec deltas and the Backlog.md '
            'task in the background; you review them here when it is done.',
            style: T.tiny,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(hintText: 'e.g. the aerial sidebar follows the file shown in the source window'),
          ),
          const SizedBox(height: 12),
          DialogButtons(cancel: _cancel, okLabel: 'Draft with an agent', okIcon: Icons.auto_awesome, ok: _draft),
        ],
      ),
    ),
  );
}

// Archive ------------------------------------------------------------------------------------------

/// Asks before archiving a change; pops true to archive.
class ArchiveDialog extends StatelessWidget {
  const ArchiveDialog({super.key, required this.lines});

  /// What archiving will do, one line each.
  final List<String> lines;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: C.surface,
    title: const Text('Archive this change?', style: T.title),
    content: Text(lines.join('\n'), style: T.body),
    actions: [
      DialogButtons(
        cancel: () => Navigator.pop(context, false),
        okLabel: 'Archive',
        ok: () => Navigator.pop(context, true),
      ),
    ],
  );
}

/// Cancel and a primary button, right-aligned.
class DialogButtons extends StatelessWidget {
  const DialogButtons({super.key, required this.cancel, required this.okLabel, required this.ok, this.okIcon});

  final VoidCallback cancel, ok;
  final String okLabel;
  final IconData? okIcon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      SmallButton('Cancel', onPressed: cancel),
      const SizedBox(width: 8),
      SmallButton(okLabel, icon: okIcon, primary: true, onPressed: ok),
    ],
  );
}
