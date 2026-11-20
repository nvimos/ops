import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../local/browser.dart';
import '../local/editors.dart';
import '../local/terminals.dart';
import '../state/prefs.dart' show Settings;
import '../state/settings.dart';
import 'error_view.dart';
import 'mode_rail.dart' show Mode, ModeText, RailState;
import 'nav_keys.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Settings mode: the editor files open in, the terminal and folder opener of the Repos rows,
/// and how deep the crawl goes. Page: owns the keys; [SettingsState] does the work.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.state, this.layout, this.onRail});

  final SettingsState state;

  /// The rail's order and hidden modes; the shell's instance, so a show updates the rail at once.
  final RailState? layout;

  /// Gives the keyboard to the mode rail (Left, Tab round the cycle).
  final VoidCallback? onRail;

  @override
  State<SettingsView> createState() => SettingsViewState();
}

class SettingsViewState extends State<SettingsView> {
  final focus = FocusNode(debugLabel: 'settings');
  final _command = TextEditingController();

  SettingsState get st => widget.state;

  /// On its own (tests) the view makes a state from the same prefs; the shell passes its own.
  late final RailState _layout = widget.layout ?? RailState(st.session.prefs);

  @override
  void initState() {
    super.initState();
    _command.text = st.savedEditor ?? '';
  }

  @override
  void dispose() {
    focus.dispose();
    _command.dispose();
    // Only the state the view made itself; the shell's belongs to the shell.
    if (widget.layout == null) _layout.dispose();
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
      listenable: Listenable.merge([st, _layout]),
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
      for (final o in st.editors)
        _EditorRow(
          option: o,
          inUse: o == st.editorInUse,
          // Clicking the one detection already picked is no change; any other row becomes the choice.
          onPick: o == st.editorInUse && st.savedEditor == null ? null : () => st.chooseEditor(o.command),
        ),
      _CommandField(controller: _command, onSave: _saveCommand, onDetected: _useDetected, custom: st.savedEditor != null, onTest: _test),
      const _Section('TERMINAL', 'Started in a repository by its row in Repos.'),
      for (final t in st.terminals) _TerminalRow(option: t, inUse: t.id == st.terminalInUse?.id, onPick: () => st.chooseTerminal(t.id)),
      if (st.terminals.isEmpty) const _Note('No terminal found on PATH.'),
      const _Section('FOLDERS', 'What a repository folder opens in.'),
      _Choice(label: 'File manager', on: !st.folderInEditor, onTap: () => st.setFolderInEditor(false)),
      _Choice(label: 'The editor', on: st.folderInEditor, onTap: () => st.setFolderInEditor(true)),
      const _Section('DELETE', 'Where the Delete action of Add and Ignore puts a file.'),
      _Choice(label: 'To the trash', hint: 'the Recycle Bin, the Trash', on: st.deleteToTrash, onTap: () => st.setDeleteToTrash(true)),
      _Choice(label: 'For good', hint: 'no way back', on: !st.deleteToTrash, onTap: () => st.setDeleteToTrash(false)),
      const _Section('CONFIRM', 'Whether Delete asks before it acts.'),
      _Choice(label: 'Ask first', hint: 'a dialog names what goes', on: st.confirmDelete, onTap: () => st.setConfirmDelete(true)),
      _Choice(label: 'At once', hint: 'no question', on: !st.confirmDelete, onTap: () => st.setConfirmDelete(false)),
      const _Section('WHEEL', 'Rows one Shift + wheel notch moves a list.'),
      _NumberField(
        value: st.wheelStep,
        unit: 'rows',
        min: Settings.wheelStepMin,
        max: Settings.wheelStepMax,
        onChange: st.setWheelStep,
      ),
      const _Section('PREVIEW', 'The preview of the highlighted files in Add and Ignore (v).'),
      _Choice(
        label: 'Draw the first pages of a PDF',
        hint: st.renderPdf ? 'on' : 'off: a sentence and an Open button',
        on: st.renderPdf,
        onTap: () => st.setRenderPdf(!st.renderPdf),
      ),
      const _Section('CRAWL', 'How many levels below its start folder the crawl looks for repositories.'),
      _Depth(depth: st.scanDepth, onChange: st.setScanDepth),
      const _Section('MODES', 'Drag the rail icons to reorder them; right-click one to hide it.'),
      if (_layout.hidden.isEmpty)
        const _Note('No mode is hidden.')
      else
        for (final m in _layout.order.where(_layout.hidden.contains))
          _HiddenMode(mode: m, onShow: () => _layout.show(m)),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: 'The default order, with every mode shown',
            child: SmallButton('Reset the rail', onPressed: _layout.reset),
          ),
        ),
      ),
    ],
  );

  /// Test: open the repository's `PLAN.md` (or the app's) in the editor in use.
  Future<void> _test() async {
    final err = await st.testEditor();
    if (mounted) showActionError(context, err);
  }
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

/// A hidden mode in Settings: the icon and the name, and a click anywhere shows it again on the rail.
class _HiddenMode extends StatelessWidget {
  const _HiddenMode({required this.mode, required this.onShow});

  final Mode mode;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Put ${mode.label} back on the rail',
    child: HoverRow(
      onTap: onShow,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        children: [
          Icon(mode.icon, size: 15, color: C.muted),
          const SizedBox(width: 8),
          Text(mode.label, style: T.body),
          const Spacer(),
          Text('Show', style: T.small.copyWith(color: C.accent)),
        ],
      ),
    ),
  );
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

/// A detected editor; the one in use is marked, and a click on another row makes it the choice.
class _EditorRow extends StatelessWidget {
  const _EditorRow({required this.option, required this.inUse, this.onPick});

  final EditorOption option;
  final bool inUse;

  /// Use this editor; null for the one already in use.
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: inUse ? 'The editor in use' : 'Use ${option.label}',
    child: _Choice(label: option.label, on: inUse, hint: option.command, onTap: onPick),
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

/// The user's own editor command, with `{file}` and `{line}`, and a Test button that opens PLAN.md.
class _CommandField extends StatelessWidget {
  const _CommandField({
    required this.controller,
    required this.onSave,
    required this.onDetected,
    required this.custom,
    required this.onTest,
  });

  final TextEditingController controller;
  final VoidCallback onSave, onDetected, onTest;
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
        Tooltip(message: 'Open PLAN.md in this editor', child: SmallButton('Test', onPressed: onTest)),
        const SizedBox(width: 6),
        if (custom) SmallButton('Use the detected one', onPressed: onDetected),
      ],
    ),
  );
}

/// A whole number from [min] to [max], saved as it is typed; a value out of range says so and is not
/// saved (as in Purrage's Settings).
class _NumberField extends StatefulWidget {
  const _NumberField({required this.value, required this.unit, required this.min, required this.max, required this.onChange});

  final int value;
  final String unit;
  final int min, max;
  final ValueChanged<int> onChange;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _text = TextEditingController(text: '${widget.value}');
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final n = int.tryParse(text.trim());
    final ok = n != null && n >= widget.min && n <= widget.max;
    setState(() => _problem = ok ? null : '${widget.min} to ${widget.max}');
    if (ok) widget.onChange(n);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: TextField(
            controller: _text,
            onChanged: _typed,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: T.body,
            decoration: InputDecoration(suffixText: widget.unit, errorText: _problem),
          ),
        ),
        const SizedBox(width: 10),
        Text('range ${widget.min} to ${widget.max}', style: T.tiny),
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
