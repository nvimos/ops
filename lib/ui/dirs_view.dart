import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/dirs.dart';
import 'error_view.dart';
import 'key_sequence.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Directories mode: the start dirs (genja-startdirs' order, else recent files' dirs), a
/// filter, and the Active Directory. Picking moves the connected Neovim there (`:cd`), or starts a
/// new Neovim there when "New Neovim per directory" is on.
///
/// Page: owns keys and event handlers; [DirsState] does the work.
class DirsView extends StatefulWidget {
  const DirsView({super.key, required this.state});

  final DirsState state;

  @override
  State<DirsView> createState() => DirsViewState();
}

class DirsViewState extends State<DirsView> {
  final focus = FocusNode(debugLabel: 'dirs');
  final _filterFocus = FocusNode(debugLabel: 'dirs filter');
  final _filter = TextEditingController();
  Timer? _auto;
  static const _far = 1 << 20;
  late final _keys = KeySequence({
    'j': () => st.move(1),
    'k': () => st.move(-1),
    'gg': () => st.move(-_far),
    'G': () => st.move(_far),
    'n': st.toggleNewNeovim,
  });

  DirsState get st => widget.state;

  @override
  void dispose() {
    _keys.dispose();
    _auto?.cancel();
    focus.dispose();
    _filterFocus.dispose();
    _filter.dispose();
    super.dispose();
  }

  // Event handlers -------------------------------------------------------------------------------

  Future<void> _pick(String dir) async {
    _auto?.cancel();
    final err = await st.pick(dir);
    if (mounted) showActionError(context, err);
  }

  void _pickCursor() {
    final shown = st.shown;
    if (shown.isNotEmpty) _pick(shown[st.cursor.clamp(0, shown.length - 1)]);
  }

  void _tap(String dir) {
    focus.requestFocus();
    _pick(dir);
  }

  /// When the filter leaves one dir, it becomes the Active Directory after a short pause, so
  /// typing on doesn't switch to a dir the next key filters out anyway.
  void _filtered(String q) {
    st.setFilter(q);
    _auto?.cancel();
    final hits = st.shown;
    if (q.trim().isEmpty || hits.length != 1 || hits.single == st.active) return;
    _auto = Timer(const Duration(milliseconds: 300), () {
      if (mounted && st.shown.length == 1) _pick(st.shown.single);
    });
  }

  void _clearFilter() {
    _filter.clear();
    st.setFilter('');
  }

  // Keys: j/k, gg/G, Ctrl+D/U move, Enter picks, / or Tab filters, n toggles, Esc clears the filter.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    final k = e.logicalKey;
    if (_filterFocus.hasFocus) return _filterKey(k);
    final action = switch (k) {
      LogicalKeyboardKey.keyD when hw.isControlPressed => () => st.move(10),
      LogicalKeyboardKey.keyU when hw.isControlPressed => () => st.move(-10),
      _ when hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed => null,
      LogicalKeyboardKey.arrowDown => () => st.move(1),
      LogicalKeyboardKey.arrowUp => () => st.move(-1),
      LogicalKeyboardKey.enter => _pickCursor,
      LogicalKeyboardKey.slash || LogicalKeyboardKey.tab => _filterFocus.requestFocus,
      LogicalKeyboardKey.escape when _filter.text.isNotEmpty => _clearFilter,
      _ => null,
    };
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    return _keys.press(e.character) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// In the filter: Esc, Tab or arrow down go back to the list.
  KeyEventResult _filterKey(LogicalKeyboardKey k) {
    const back = [LogicalKeyboardKey.escape, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.tab];
    if (!back.contains(k)) return KeyEventResult.ignored;
    focus.requestFocus();
    return KeyEventResult.handled;
  }

  // Layout -------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onKeyEvent: _onKey,
    child: ListenableBuilder(
      listenable: st,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DirsHeader(source: st.dirs?.source, newNeovim: st.newNeovim, onToggle: st.toggleNewNeovim, onReload: st.load),
          _DirsFilter(controller: _filter, focus: _filterFocus, onChanged: _filtered, onSubmitted: _pickCursor),
          Expanded(child: _body()),
        ],
      ),
    ),
  );

  Widget _body() {
    if (st.error != null) return ErrorPane(st.error!, onRetry: st.load);
    if (st.dirs == null) return Empty(st.loading ? 'Loading…' : 'No list yet.');
    if (st.shown.isEmpty) return const Empty('No directory matches.');
    return _DirList(dirs: st.shown, cursor: st.cursor, active: st.active, onTap: _tap);
  }
}

// Organisms ---------------------------------------------------------------------------------------

class _DirsHeader extends StatelessWidget {
  const _DirsHeader({required this.source, required this.newNeovim, required this.onToggle, required this.onReload});

  final String? source;
  final bool newNeovim;
  final VoidCallback onToggle, onReload;

  @override
  Widget build(BuildContext context) => PaneHeader(
    title: Row(
      children: [
        const Text('Directories'),
        const SizedBox(width: 8),
        if (source != null) Text(source == 'startdirs' ? 'from genja-startdirs' : 'from recent files', style: T.tiny),
      ],
    ),
    trailing: [
      _NewNeovimSwitch(on: newNeovim, onToggle: onToggle),
      IconButton(
        tooltip: 'Reload the list',
        iconSize: 16,
        onPressed: onReload,
        icon: const Icon(Icons.refresh, color: C.muted),
      ),
    ],
  );
}

class _DirsFilter extends StatelessWidget {
  const _DirsFilter({required this.controller, required this.focus, required this.onChanged, required this.onSubmitted});

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: TextField(
      controller: controller,
      focusNode: focus,
      style: T.body,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, size: 15, color: C.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 30),
        suffixIcon: ClearButton(controller: controller, onCleared: onChanged),
        suffixIconConstraints: ClearButton.constraints,
        hintText: 'Filter (/)',
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted(),
    ),
  );
}

class _DirList extends StatelessWidget {
  const _DirList({required this.dirs, required this.cursor, required this.active, required this.onTap});

  final List<String> dirs;
  final int cursor;
  final String? active;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final a = active?.toLowerCase();
    return ListView.builder(
      itemCount: dirs.length,
      itemBuilder: (context, i) => DirRow(
        dir: dirs[i],
        selected: i == cursor,
        active: dirs[i].toLowerCase() == a,
        onTap: () => onTap(dirs[i]),
      ),
    );
  }
}

// Molecules and atoms -----------------------------------------------------------------------------

/// A dir in the list; the Active Directory is marked.
class DirRow extends StatelessWidget {
  const DirRow({super.key, required this.dir, required this.selected, required this.active, required this.onTap});

  final String dir;
  final bool selected, active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverRow(
    selected: selected,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    child: Row(
      children: [
        Icon(active ? Icons.folder_special : Icons.folder_outlined, size: 15, color: active ? C.accent : C.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(dir, style: active ? T.body.copyWith(color: C.accent) : T.body, overflow: TextOverflow.ellipsis),
        ),
        if (active) const Text('Active Directory', style: T.tiny),
      ],
    ),
  );
}

class _NewNeovimSwitch extends StatelessWidget {
  const _NewNeovimSwitch({required this.on, required this.onToggle});

  final bool on;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Picking a dir starts a new Neovim there instead of moving this one (n)',
    child: Row(
      children: [
        const Text('New Neovim per directory', style: T.small),
        Transform.scale(scale: .7, child: Switch(value: on, onChanged: (_) => onToggle())),
      ],
    ),
  );
}
