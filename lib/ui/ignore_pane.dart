import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../backend/models.dart';
import '../local/ignore_edits.dart';
import '../state/ignore_pane.dart';
import 'error_view.dart';
import 'reveal.dart';
import 'theme.dart';
import 'widgets.dart';

/// One line's height, from the text style: every line is the same height, so centring one is one
/// `jumpTo` with no layout pass to measure first. The height follows the style, not a constant.
double get ignoreLineExtent => (T.code.fontSize ?? 12.5) * (T.code.height ?? 1.35) + 6;

/// The Ignore panes: on the left every `.gitignore` of the project (the project one first), on the
/// right every line of the selected file as it is; comments and blank lines too, without numbers.
/// A line can be deleted, taken one folder up, flipped or opened; [IgnorePaneState] does the work.
class IgnorePane extends StatefulWidget {
  const IgnorePane({
    super.key,
    required this.state,
    required this.filesFocus,
    required this.linesFocus,
    this.wheelStep = 5,
  });

  final IgnorePaneState state;

  /// The two Tab stops of the panes: the file list, and the lines.
  final FocusNode filesFocus, linesFocus;

  /// Lines one Shift + wheel notch scrolls the rules by (a setting).
  final int wheelStep;

  @override
  State<IgnorePane> createState() => _IgnorePaneState();
}

class _IgnorePaneState extends State<IgnorePane> {
  /// The files that govern the cursor row's folder, kept while the cursor moves inside one folder.
  late Set<String> _governing = widget.state.governing;

  IgnorePaneState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.add.addListener(_onAdd);
  }

  @override
  void dispose() {
    state.add.removeListener(_onAdd);
    super.dispose();
  }

  /// A cursor move only re-marks the rail, and only when the folder under the cursor changed.
  void _onAdd() {
    final next = state.governing;
    if (setEquals(next, _governing)) return;
    setState(() => _governing = next);
  }

  /// Run one line or file action; a done edit says so with Undo, a refusal says why.
  Future<void> _run(Future<IgnoreEdit> action) async {
    final edit = await action;
    if (!mounted) return;
    if (!edit.ok) return showActionError(context, edit.refusal);
    final undo = edit.undo;
    if (undo == null) return;
    showAutoStatus(context, edit.message!, onUndo: () async {
      final undone = await undo();
      if (mounted && !undone.ok) showActionError(context, undone.refusal);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, widget.filesFocus, widget.linesFocus]),
    builder: (context, _) => _pane(context),
  );

  Widget _pane(BuildContext context) {
    final lit = widget.filesFocus.hasFocus || widget.linesFocus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: Text(
            state.selected?.path ?? 'Ignore rules',
            overflow: TextOverflow.ellipsis,
            style: lit ? T.title : T.title.copyWith(color: C.muted),
          ),
          trailing: [
            if (state.loading) const Spinner(),
            const SizedBox(width: 6),
            IconAction(
              icon: Icons.open_in_new,
              tooltip: 'Open the selected .gitignore in the editor',
              onPressed: () => _run(state.openSelected()),
            ),
            IconAction(
              icon: Icons.note_add_outlined,
              tooltip: "New here: create a .gitignore in the cursor row's folder",
              onPressed: () => _run(state.createHere()),
            ),
          ],
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (!state.available) return const Empty('Ignore rules need a repository.');
    if (state.error != null) return ErrorPane(state.error!, onRetry: state.load);
    if (state.files.isEmpty && state.loading) return const Empty('Loading…');
    if (state.files.isEmpty) return _NoFiles(onCreate: () => _run(state.createProject()));
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: math.max(80, box.maxWidth * .35), child: _filesPane()),
          const VerticalDivider(width: 1),
          Expanded(child: _linesPane()),
        ],
      ),
    );
  }

  Widget _filesPane() => Focus(
    focusNode: widget.filesFocus,
    child: _Files(
      state: state,
      governing: _governing,
      onTap: (file) {
        widget.filesFocus.requestFocus();
        state.pick(file);
      },
    ),
  );

  Widget _linesPane() => Focus(
    focusNode: widget.linesFocus,
    child: _Lines(state: state, wheelStep: widget.wheelStep, linesFocus: widget.linesFocus, onRun: _run),
  );
}

/// The left pane: every `.gitignore`, with the selected one kept in view. Each row is the same
/// height, so the reveal is one jump.
class _Files extends StatefulWidget {
  const _Files({required this.state, required this.governing, required this.onTap});

  final IgnorePaneState state;
  final Set<String> governing;
  final ValueChanged<IgnoreFileRef> onTap;

  @override
  State<_Files> createState() => _FilesState();
}

class _FilesState extends State<_Files> {
  final scroll = ScrollController();
  String? _seen;
  static const extent = 30.0;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// Keep the selected file in view when j / k or a pick moved it.
  void _revealAfterFrame() {
    final at = widget.state.files.indexWhere((f) => f == widget.state.selected);
    final path = widget.state.selected?.path;
    if (at < 0 || path == _seen) return;
    _seen = path;
    WidgetsBinding.instance.addPostFrameCallback((_) => revealRange(scroll, at * extent, extent));
  }

  @override
  Widget build(BuildContext context) {
    _revealAfterFrame();
    return ListView.builder(
      controller: scroll,
      itemExtent: extent,
      itemCount: widget.state.files.length,
      itemBuilder: (context, i) {
        final file = widget.state.files[i];
        return _FileTile(
          label: IgnorePaneState.labelOf(file),
          path: file.path,
          selected: file == widget.state.selected,
          governs: widget.governing.contains(file.path),
          onTap: () => widget.onTap(file),
        );
      },
    );
  }
}

/// A file in the left pane: its folder (or "project .gitignore"), with the marker that says it
/// governs the cursor row's folder. It only marks; the selection stays where the user put it.
class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.label,
    required this.path,
    required this.selected,
    required this.governs,
    required this.onTap,
  });

  final String label, path;
  final bool selected, governs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverRow(
    key: ValueKey('ignore-file-$path'),
    onTap: onTap,
    selected: selected,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 14,
          child: governs
              ? const Tooltip(
                  message: "Applies to the cursor row's folder",
                  child: Icon(Icons.circle, size: 6, color: C.accent),
                )
              : null,
        ),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.code.copyWith(color: selected ? C.text : C.muted),
          ),
        ),
      ],
    ),
  );
}

/// The selected file's lines, one row each, no numbers. A cursor is on one line; j / k move it,
/// Delete removes it, Enter opens the file at it. Shift + wheel scrolls the lines by a setting.
class _Lines extends StatefulWidget {
  const _Lines({required this.state, required this.wheelStep, required this.linesFocus, required this.onRun});

  final IgnorePaneState state;
  final int wheelStep;
  final FocusNode linesFocus;
  final Future<void> Function(Future<IgnoreEdit> action) onRun;

  @override
  State<_Lines> createState() => _LinesState();
}

class _LinesState extends State<_Lines> {
  final scroll = ScrollController();
  int _seenCentre = 0;
  int _seenCursor = -1;

  IgnorePaneState get state => widget.state;
  double get extent => ignoreLineExtent;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// A write asks for a line in the middle; moving the cursor only keeps it in view.
  void _followAfterFrame() {
    if (state.centreRequest != _seenCentre) {
      _seenCentre = state.centreRequest;
      final line = state.centreLine;
      WidgetsBinding.instance.addPostFrameCallback((_) => _centre(line));
      return;
    }
    if (state.lineCursor != _seenCursor) {
      _seenCursor = state.lineCursor;
      final top = (state.lineCursor - 1) * extent;
      WidgetsBinding.instance.addPostFrameCallback((_) => revealRange(scroll, top, extent));
    }
  }

  /// Put [line] (1-based) in the middle of the pane at once, without an animated scroll.
  void _centre(int line) {
    if (!scroll.hasClients || line < 1) return;
    final p = scroll.position;
    final top = (line - 1) * extent;
    final centred = top - (p.viewportDimension - extent) / 2;
    scroll.jumpTo(centred.clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  /// Shift + wheel scrolls [wheelStep] lines a notch. Claiming the signal keeps the list from also
  /// scrolling its own way.
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !HardwareKeyboard.instance.isShiftPressed) return;
    final dy = event.scrollDelta.dy != 0 ? event.scrollDelta.dy : event.scrollDelta.dx;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _scrollLines(dy > 0 ? widget.wheelStep : -widget.wheelStep),
    );
  }

  void _scrollLines(int lines) {
    if (!scroll.hasClients) return;
    final p = scroll.position;
    final target = p.pixels + lines.clamp(-1 << 20, 1 << 20) * extent;
    scroll.jumpTo(target.clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    _followAfterFrame();
    return Listener(
      onPointerSignal: _wheel,
      child: state.lines.isEmpty
          ? const Empty('No lines in this file.')
          : ListView.builder(
              controller: scroll,
              itemExtent: extent,
              itemCount: state.lines.length,
              itemBuilder: (context, i) => _LineTile(
                text: state.lines[i],
                cursor: i + 1 == state.lineCursor,
                onTap: () {
                  widget.linesFocus.requestFocus();
                  widget.state.pickLine(i + 1);
                },
                onMenu: (at) => _menu(context, i + 1, state.lines[i], at),
                onDelete: () => widget.onRun(state.deleteLine(i + 1)),
                onDirname: IgnoreEdits.dirname(state.lines[i]).ok
                    ? () => widget.onRun(state.dirnameLine(i + 1))
                    : null,
                dirnameTip: IgnoreEdits.dirname(state.lines[i]).refusal ?? 'Dirname: take the rule one folder up',
              ),
            ),
    );
  }

  /// The line menu: Delete, Dirname, Flip, Open. A disabled item's tooltip says why.
  Future<void> _menu(BuildContext context, int number, String text, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final dirname = IgnoreEdits.dirname(text);
    final flip = IgnoreEdits.flip(text);
    final choice = await showMenu<_LineMenu>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(
          value: _LineMenu.delete,
          height: 32,
          child: Tooltip(message: 'Remove this line from the file', child: Text('Delete')),
        ),
        PopupMenuItem(
          value: _LineMenu.dirname,
          enabled: dirname.ok,
          height: 32,
          child: Tooltip(
            message: dirname.refusal ?? 'Dirname: take the rule one folder up',
            child: const Text('Dirname'),
          ),
        ),
        PopupMenuItem(
          value: _LineMenu.flip,
          enabled: flip.ok,
          height: 32,
          child: Tooltip(
            message: flip.refusal ?? 'Flip: add or remove the leading !',
            child: const Text('Flip'),
          ),
        ),
        PopupMenuItem(
          value: _LineMenu.open,
          height: 32,
          child: Tooltip(message: 'Open this .gitignore in the editor at line $number', child: const Text('Open')),
        ),
      ],
    );
    switch (choice) {
      case _LineMenu.delete:
        await widget.onRun(state.deleteLine(number));
      case _LineMenu.dirname:
        await widget.onRun(state.dirnameLine(number));
      case _LineMenu.flip:
        await widget.onRun(state.flipLine(number));
      case _LineMenu.open:
        await widget.onRun(state.openSelected(line: number));
      case null:
        break;
    }
  }
}

/// What a line's right-click menu offers.
enum _LineMenu { delete, dirname, flip, open }

/// One line of the file: its text, the cursor tint, the hover buttons, and the right-click menu.
class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.text,
    required this.cursor,
    required this.onTap,
    required this.onMenu,
    required this.onDelete,
    required this.onDirname,
    required this.dirnameTip,
  });

  final String text;
  final bool cursor;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final VoidCallback onDelete;

  /// Null when Dirname is refused for this line.
  final VoidCallback? onDirname;
  final String dirnameTip;

  @override
  Widget build(BuildContext context) => HoverRow(
    selected: cursor,
    onTap: onTap,
    onContextMenu: onMenu,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.code)),
        _Buttons(onDelete: onDelete, onDirname: onDirname, dirnameTip: dirnameTip),
      ],
    ),
  );
}

/// The hover buttons of a line, the documented exception to "no hover-only row buttons": Dirname
/// and Delete, each with its tooltip. They sit in a fixed slot, so the text never shifts.
class _Buttons extends StatelessWidget {
  const _Buttons({required this.onDelete, required this.onDirname, required this.dirnameTip});

  final VoidCallback onDelete;
  final VoidCallback? onDirname;
  final String dirnameTip;

  @override
  Widget build(BuildContext context) {
    if (!RowHover.of(context)) return const SizedBox(width: 42);
    return SizedBox(
      width: 42,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconAction(icon: Icons.arrow_upward, tooltip: dirnameTip, onPressed: onDirname),
          IconAction(icon: Icons.delete_outline, tooltip: 'Delete this line', onPressed: onDelete, color: C.yellow),
        ],
      ),
    );
  }
}

/// A project without any `.gitignore`: say so, and offer to create the project one.
class _NoFiles extends StatelessWidget {
  const _NoFiles({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('No .gitignore files', style: T.body),
        const SizedBox(height: 10),
        Tooltip(
          message: 'Create the project .gitignore at the repository root',
          child: SmallButton('Create project .gitignore', icon: Icons.note_add_outlined, onPressed: onCreate),
        ),
      ],
    ),
  );
}
