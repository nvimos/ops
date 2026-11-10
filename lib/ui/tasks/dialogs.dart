import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';
import 'icons.dart';

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

  void _ok() => Navigator.pop(
    context,
    NewTask(
      _title.text,
      _status,
      _labels.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      _desc.text.trim(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: C.surface,
      alignment: const Alignment(0, -.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: C.border),
      ),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('New task', style: T.small),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(hintText: 'Title', filled: false, border: InputBorder.none),
                onSubmitted: (_) => _ok(),
              ),
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 6,
                style: T.body,
                decoration: const InputDecoration(
                  hintText: 'Description (optional)',
                  filled: false,
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  PopupMenuButton<String>(
                    color: C.surface2,
                    onSelected: (s) => setState(() => _status = s),
                    itemBuilder: (_) => [
                      for (final s in widget.statuses)
                        PopupMenuItem(
                          value: s,
                          height: 32,
                          child: Row(
                            children: [
                              StatusIcon(s),
                              const SizedBox(width: 8),
                              Text(s, style: T.body),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: C.border),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        children: [
                          StatusIcon(_status),
                          const SizedBox(width: 6),
                          Text(_status, style: T.small),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: TextField(
                        controller: _labels,
                        style: T.small,
                        decoration: const InputDecoration(hintText: 'labels, comma separated'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SmallButton('Create task', primary: true, onPressed: _ok),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

  void _go(int d, int n) {
    setState(() => _i = (_i + d).clamp(0, n - 1));
    if (_scroll.hasClients) {
      final top = _i * 34.0;
      if (top < _scroll.offset) _scroll.jumpTo(top);
      if (top + 34 > _scroll.offset + _scroll.position.viewportDimension) {
        _scroll.jumpTo(top + 34 - _scroll.position.viewportDimension);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return Dialog(
      backgroundColor: C.surface,
      alignment: const Alignment(0, -.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: C.border),
      ),
      child: SizedBox(
        width: 620,
        height: 420,
        child: Column(
          children: [
            Focus(
              onKeyEvent: (_, e) {
                if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _go(1, hits.length);
                } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _go(-1, hits.length);
                } else if (e.logicalKey == LogicalKeyboardKey.enter && hits.isNotEmpty) {
                  Navigator.pop(context, hits[_i]);
                } else {
                  return KeyEventResult.ignored;
                }
                return KeyEventResult.handled;
              },
              child: TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Type a command or search…',
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
                onChanged: (v) => setState(() {
                  _q = v;
                  _i = 0;
                }),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemExtent: 34,
                itemCount: hits.length,
                itemBuilder: (_, i) => HoverRow(
                  selected: i == _i,
                  onTap: () => Navigator.pop(context, hits[i]),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(hits[i].icon, size: 15, color: C.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(hits[i].label, style: T.body, overflow: TextOverflow.ellipsis),
                      ),
                      Text(hits[i].hint, style: T.tiny),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: C.surface,
      alignment: const Alignment(0, -.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: C.border),
      ),
      child: SizedBox(
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
                decoration: const InputDecoration(
                  hintText: 'e.g. the aerial sidebar follows the file shown in the source window',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallButton('Cancel', onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  SmallButton(
                    'Draft with an agent',
                    icon: Icons.auto_awesome,
                    primary: true,
                    onPressed: () => Navigator.pop(context, _text.text.trim()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
