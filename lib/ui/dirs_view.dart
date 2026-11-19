import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../state/repos.dart';
import 'error_view.dart';
import 'key_sequence.dart';
import 'nav_keys.dart';
import 'path_cells.dart';
import 'text_width.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Repos mode: the repositories the crawl finds, ordered by the hints (the open one, the start
/// dirs of a connected Neovim, the recent folders; stale ones greyed, with Remove), a filter, and the
/// Active Directory. Picking opens a repository locally, or with Neovim moves it there (`:cd`) or
/// starts a new Neovim when "New Neovim per directory" is on.
///
/// Page: owns keys and event handlers; [ReposState] does the work.
class DirsView extends StatefulWidget {
  const DirsView({super.key, required this.state, this.onRail, this.onOpen});

  final ReposState state;

  /// Gives the keyboard to the mode rail (Left, Tab round the cycle).
  final VoidCallback? onRail;

  /// A click on the Active Directory again: on to the Tasks mode.
  final VoidCallback? onOpen;

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
    '{': () => st.move(-3),
    '}': () => st.move(3),
    'gg': () => st.move(-_far),
    'G': () => st.move(_far),
    'gi': focusFilter, // go input: the filter field, as in the other modes
    'n': () => st.session.hasEditor ? st.toggleNewNeovim() : null,
    'r': st.load,
  });

  ReposState get st => widget.state;

  void _toRail() => widget.onRail?.call();

  /// Tab from the rail: the filter; Shift+Tab from the rail: the list.
  void enterFromRail({required bool forward}) => forward ? focusFilter() : focus.requestFocus();

  /// The shell calls this on a switch to Directories: the filter takes the keyboard, so typing
  /// filters at once; Esc, Tab or arrow down go to the list.
  void focusFilter() => _filterFocus.requestFocus();

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

  /// Enter in the filter: the field drops its focus on submit (to the route scope, outside the
  /// shell's keys), so the list takes the keyboard back before the pick.
  void _submitFilter() {
    focus.requestFocus();
    _pickCursor();
  }

  /// A click picks the directory; a click on the one that already is the Active Directory opens the project (the first mode with something to do).
  void _tap(String dir) {
    if (dir == st.active && widget.onOpen != null) return widget.onOpen!();
    focus.requestFocus();
    _pick(dir);
  }

  Future<void> _terminal(String path) async => _say(await st.openTerminal(path));

  Future<void> _folder(String path) async => _say(await st.openInFileManager(path));

  /// Manage, from the row's menu: make it the Active Directory and go on to the project, as Purrage's
  /// "Manage" opened the repository in Changes.
  Future<void> _manage(String path) async {
    await _pick(path);
    if (mounted) widget.onOpen?.call();
  }

  /// A right click on a row: offer what can be done to it, as Purrage's Directories list did.
  Future<void> _menu(RepoEntry entry, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<RepoMenu>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
      items: repoMenuItems(stale: entry.stale),
    );
    if (!mounted) return;
    switch (choice) {
      case RepoMenu.manage:
        _manage(entry.path);
      case RepoMenu.open:
        _folder(entry.path);
      case RepoMenu.terminal:
        _terminal(entry.path);
      case RepoMenu.crawl:
        st.scanFrom(entry.path);
      case RepoMenu.remove:
        st.remove(entry.path);
      case null:
        break;
    }
  }

  void _say(String? err) {
    if (mounted) showActionError(context, err);
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
      LogicalKeyboardKey.enter => _pickCursor,
      LogicalKeyboardKey.slash => _filterFocus.requestFocus,
      LogicalKeyboardKey.tab => hw.isShiftPressed ? _filterFocus.requestFocus : _toRail,
      LogicalKeyboardKey.escape when _filter.text.isNotEmpty => _clearFilter,
      _ => null,
    };
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    // The arrows, hjkl and wasd are one set of keys (see nav_keys.dart); a pending `g` owns the next key.
    final nav = _keys.pending || hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed ? null : navKey(e);
    if (nav != null) {
      if (nav.vertical) st.move(nav.delta);
      if (nav.dir == NavDir.left) _toRail();
      return KeyEventResult.handled;
    }
    return _keys.press(e.character) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// In the filter: Esc, Tab or arrow down go back to the list.
  KeyEventResult _filterKey(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.tab && HardwareKeyboard.instance.isShiftPressed) {
      _toRail();
      return KeyEventResult.handled;
    }
    // Left moves the text cursor, except at the leftmost edge (or in an empty field): the rail.
    if (k == LogicalKeyboardKey.arrowLeft && !HardwareKeyboard.instance.isShiftPressed && cursorAtStart(_filter)) {
      _toRail();
      return KeyEventResult.handled;
    }
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
          _ReposHeader(state: st, showNeovimSwitch: st.session.hasEditor),
          _DirsFilter(controller: _filter, focus: _filterFocus, onChanged: _filtered, onSubmitted: _submitFilter),
          Expanded(child: _body()),
        ],
      ),
    ),
  );

  Widget _body() {
    if (st.error != null) return ErrorPane(st.error!, onRetry: st.load);
    if (st.entries.isEmpty) return Empty(st.loading || st.browser.scanning ? 'Looking for repositories…' : 'No repositories found.');
    if (st.shown.isEmpty) return const Empty('No directory matches.');
    return _RepoList(
      entries: st.shownEntries,
      cursor: st.cursor,
      active: st.active,
      onTap: _tap,
      onMenu: _menu,
    );
  }
}

/// What a repository's right-click menu offers, as in Purrage.
enum RepoMenu { manage, open, terminal, crawl, remove }

/// The menu: "Manage" makes it the Active Directory and opens the project, "Open" shows the folder as
/// Settings says, "Terminal" starts a terminal there, "Crawl from here" walks from it. A stale hint
/// only offers "Remove".
List<PopupMenuEntry<RepoMenu>> repoMenuItems({required bool stale}) => stale
    ? [
        const PopupMenuItem(
          value: RepoMenu.remove,
          height: 32,
          child: Tooltip(message: 'Remove this hint from the list', child: Text('Remove')),
        ),
      ]
    : [
        const PopupMenuItem(
          value: RepoMenu.manage,
          height: 32,
          child: Tooltip(message: 'Make it the Active Directory and open the project', child: Text('Manage')),
        ),
        const PopupMenuItem(
          value: RepoMenu.open,
          height: 32,
          child: Tooltip(message: 'Open this folder: in the editor or the file manager, as Settings says', child: Text('Open')),
        ),
        const PopupMenuItem(
          value: RepoMenu.terminal,
          height: 32,
          child: Tooltip(message: 'Open a terminal in this folder', child: Text('Terminal')),
        ),
        const PopupMenuItem(
          value: RepoMenu.crawl,
          height: 32,
          child: Tooltip(message: 'Look for repositories from this folder', child: Text('Crawl from here')),
        ),
      ];

class _DirsFilter extends StatelessWidget {
  const _DirsFilter({required this.controller, required this.focus, required this.onChanged, required this.onSubmitted});

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: ClearOnAltX(
      controller: controller,
      onCleared: onChanged,
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
    ),
  );
}


// Organisms ---------------------------------------------------------------------------------------

/// The title, what the crawl is doing, and the crawl's controls: up a folder, drives, look again.
class _ReposHeader extends StatelessWidget {
  const _ReposHeader({required this.state, required this.showNeovimSwitch});

  final ReposState state;
  final bool showNeovimSwitch;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PaneHeader(
        title: Row(children: [const Text('Repos'), const SizedBox(width: 8), if (state.browser.scanning) const Spinner()]),
        trailing: [
          if (showNeovimSwitch) _NewNeovimSwitch(on: state.newNeovim, onToggle: state.toggleNewNeovim),
          IconAction(icon: Icons.arrow_upward, tooltip: 'Crawl from the parent folder', onPressed: state.scanUp),
          IconAction(icon: Icons.refresh, tooltip: 'Look again: the hints and the crawl (r)', onPressed: state.load),
        ],
      ),
      _CrawlLine(state: state),
    ],
  );
}

/// Where the crawl walks from, the drives to walk instead, and what the last walk did.
class _CrawlLine extends StatelessWidget {
  const _CrawlLine({required this.state});

  final ReposState state;

  String get _status {
    final b = state.browser;
    if (b.scanning) return 'looking… ${b.repos.length} found';
    return state.lastReport?.summary ?? '';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
    child: Row(
      children: [
        const Icon(Icons.travel_explore, size: 14, color: C.muted),
        const SizedBox(width: 6),
        Tooltip(
          message: 'The crawl walks from here, ${state.browser.maxDepth} levels down',
          child: Text(state.crawlFolder, style: T.small),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(_status, style: T.tiny, overflow: TextOverflow.ellipsis)),
        _Drives(state: state),
      ],
    ),
  );
}

/// One small button per drive (Windows): the crawl starts from its root.
class _Drives extends StatefulWidget {
  const _Drives({required this.state});

  final ReposState state;

  @override
  State<_Drives> createState() => _DrivesState();
}

class _DrivesState extends State<_Drives> {
  late final Future<List<String>> _drives = widget.state.drives();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _drives,
    builder: (context, snap) => Row(
      children: [
        for (final d in snap.data ?? const <String>[])
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tooltip(
              message: 'Crawl the whole drive $d',
              child: SmallButton(d, onPressed: () => widget.state.scanFrom(d)),
            ),
          ),
      ],
    ),
  );
}

class _RepoList extends StatelessWidget {
  const _RepoList({required this.entries, required this.cursor, required this.active, required this.onTap, required this.onMenu});

  final List<RepoEntry> entries;
  final int cursor;
  final String? active;
  final ValueChanged<String> onTap;

  /// A right click on a row, with the row and where it happened.
  final void Function(RepoEntry entry, Offset at) onMenu;

  @override
  Widget build(BuildContext context) {
    final a = active?.toLowerCase();
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) => DirRow(
        entry: entries[i],
        selected: i == cursor,
        active: entries[i].path.toLowerCase() == a,
        onTap: () => onTap(entries[i].path),
        onMenu: (at) => onMenu(entries[i], at),
      ),
    );
  }
}

// Molecules and atoms -----------------------------------------------------------------------------

const _sourceLabels = {
  'connected': 'open',
  'active': 'open',
  'startdirs': 'start dirs',
  'recent': 'recent',
  'found': '',
};

/// The room a row's label takes: the widest of them, so the folder and name columns before it stay
/// the same width on every row.
final double _labelWidth = [
  'no longer a repository',
  'Active Directory',
  ..._sourceLabels.values.where((s) => s.isNotEmpty),
].map((s) => textWidth(s, T.tiny)).fold(0, (a, b) => a > b ? a : b);

/// A repository in the list: the folder right-aligned, the name in the folder amber, as in Purrage. The
/// Active Directory keeps the amber name and is marked by the accent bar, the accent tint and its label;
/// a stale hint is greyed. There are no row buttons: a right click opens the row's menu.
class DirRow extends StatelessWidget {
  const DirRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.active,
    required this.onTap,
    required this.onMenu,
  });

  final RepoEntry entry;
  final bool selected, active;
  final VoidCallback onTap;

  /// A right click, with where it happened.
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final (folder, name) = splitPath(entry.path);
    final marked = active || selected;
    return HoverRow(
      selected: selected || active,
      selectedColor: active ? C.current : C.surface2,
      bar: marked ? C.accent : Colors.transparent,
      onTap: entry.stale ? null : onTap,
      onContextMenu: onMenu,
      padding: const EdgeInsets.fromLTRB(11, 7, 14, 7),
      child: Row(
        children: [
          Icon(
            active ? Icons.folder_special : Icons.folder_outlined,
            size: 15,
            color: entry.stale ? C.faint : (active ? C.accent : C.muted),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: PathFolder(folder)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: PathName(name, color: entry.stale ? C.faint : C.folder)),
          const SizedBox(width: 8),
          SizedBox(width: _labelWidth, child: _RowLabel(entry: entry, active: active)),
        ],
      ),
    );
  }
}

/// The end of a row, right-aligned in a fixed slot: what the hint is, "Active Directory", or that the
/// folder is gone.
class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.entry, required this.active});

  final RepoEntry entry;
  final bool active;

  String get _text => entry.stale
      ? 'no longer a repository'
      : active
      ? 'Active Directory'
      : (_sourceLabels[entry.source] ?? '');

  @override
  Widget build(BuildContext context) => Text(
    _text,
    textAlign: TextAlign.right,
    overflow: TextOverflow.ellipsis,
    maxLines: 1,
    style: active ? T.tiny.copyWith(color: C.accent) : T.tiny,
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
