import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../local/browser.dart';
import '../local/editors.dart';
import '../local/terminals.dart';
import '../state/settings.dart';
import 'nav_keys.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Settings mode: the editor files open in, the terminal and folder opener of the Repos rows,
/// and how deep the crawl goes. Page: owns the keys; [SettingsState] does the work.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.state, this.onRail});

  final SettingsState state;

  /// Gives the keyboard to the mode rail (Left, Tab round the cycle).
  final VoidCallback? onRail;

  @override
  State<SettingsView> createState() => SettingsViewState();
}

class SettingsViewState extends State<SettingsView> {
  final focus = FocusNode(debugLabel: 'settings');
  final _command = TextEditingController();

  SettingsState get st => widget.state;

  @override
  void initState() {
    super.initState();
    _command.text = st.savedEditor ?? '';
  }

  @override
  void dispose() {
    focus.dispose();
    _command.dispose();
    super.dispose();
  }

  /// Tab from the rail: the page; Shift+Tab: the same (a short page has one stop).
  void enterFromRail({required bool forward}) => focus.requestFocus();

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.tab || navKey(e)?.dir == NavDir.left) {
      widget.onRail?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _saveCommand() => st.chooseEditor(_command.text);

  void _useDetected() {
    _command.clear();
    st.chooseEditor(null);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onKeyEvent: _onKey,
    child: ListenableBuilder(
      listenable: st,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneHeader(
            title: const Text('Settings'),
            trailing: [
              if (st.detecting) const Spinner(),
              IconAction(icon: Icons.refresh, tooltip: 'Look for editors and terminals again', onPressed: st.detect),
            ],
          ),
          Expanded(child: _page()),
        ],
      ),
    ),
  );

  Widget _page() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      _Section('EDITOR', 'Files open here at their line: Open in Neovim, a diff line, a task file.'),
      for (final o in st.editors) _EditorRow(option: o, inUse: o == st.editorInUse),
      _CommandField(controller: _command, onSave: _saveCommand, onDetected: _useDetected, custom: st.savedEditor != null),
      const _Section('TERMINAL', 'Started in a repository by its row in Repos.'),
      for (final t in st.terminals) _TerminalRow(option: t, inUse: t.id == st.terminalInUse?.id, onPick: () => st.chooseTerminal(t.id)),
      if (st.terminals.isEmpty) const _Note('No terminal found on PATH.'),
      const _Section('FOLDERS', 'What a repository folder opens in.'),
      _Choice(label: 'File manager', on: !st.folderInEditor, onTap: () => st.setFolderInEditor(false)),
      _Choice(label: 'The editor', on: st.folderInEditor, onTap: () => st.setFolderInEditor(true)),
      const _Section('CRAWL', 'How many levels below its start folder the crawl looks for repositories.'),
      _Depth(depth: st.scanDepth, onChange: st.setScanDepth),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.hint);

  final String title, hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(title, style: T.section), Text(hint, style: T.tiny)],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: Text(text, style: T.small));
}

/// A radio row: a mark, a label and a hint line.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.on, required this.onTap, this.hint = ''});

  final String label, hint;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => HoverRow(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
    child: Row(
      children: [
        Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 15, color: on ? C.accent : C.muted),
        const SizedBox(width: 8),
        Text(label, style: T.body),
        const SizedBox(width: 10),
        Expanded(child: Text(hint, style: T.tiny, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// A detected editor; the one in use is marked. The list is the detection order, not a choice: to
/// pick another, type its command below.
class _EditorRow extends StatelessWidget {
  const _EditorRow({required this.option, required this.inUse});

  final EditorOption option;
  final bool inUse;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: inUse ? 'The editor in use' : 'Found, but another one comes first (a saved command leads)',
    child: _Choice(label: option.label, on: inUse, hint: option.command, onTap: null),
  );
}

class _TerminalRow extends StatelessWidget {
  const _TerminalRow({required this.option, required this.inUse, required this.onPick});

  final TerminalOption option;
  final bool inUse;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Use ${option.label} for the terminal button',
    child: _Choice(label: option.label, on: inUse, hint: option.exe, onTap: onPick),
  );
}

/// The user's own editor command, with `{file}` and `{line}`.
class _CommandField extends StatelessWidget {
  const _CommandField({required this.controller, required this.onSave, required this.onDetected, required this.custom});

  final TextEditingController controller;
  final VoidCallback onSave, onDetected;
  final bool custom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: T.body,
            decoration: const InputDecoration(hintText: 'Your own command, e.g.  code --goto {file}:{line}'),
            onSubmitted: (_) => onSave(),
          ),
        ),
        const SizedBox(width: 8),
        SmallButton('Save', primary: true, onPressed: onSave),
        const SizedBox(width: 6),
        if (custom) SmallButton('Use the detected one', onPressed: onDetected),
      ],
    ),
  );
}

/// The crawl depth as a small stepper.
class _Depth extends StatelessWidget {
  const _Depth({required this.depth, required this.onChange});

  final int depth;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Row(
      children: [
        IconAction(icon: Icons.remove, tooltip: 'One level less', onPressed: depth > RepoBrowser.depthMin ? () => onChange(depth - 1) : null),
        SizedBox(width: 36, child: Center(child: Text('$depth', style: T.body))),
        IconAction(icon: Icons.add, tooltip: 'One level more', onPressed: depth < RepoBrowser.depthMax ? () => onChange(depth + 1) : null),
        const SizedBox(width: 8),
        Text('levels (${RepoBrowser.depthMin}–${RepoBrowser.depthMax}); applies to the next crawl', style: T.tiny),
      ],
    ),
  );
}
