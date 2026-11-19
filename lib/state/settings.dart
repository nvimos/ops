import 'package:flutter/foundation.dart';

import '../local/browser.dart';
import '../local/editors.dart';
import '../local/terminals.dart';
import 'prefs.dart';
import 'session.dart';

/// State of the Settings mode: the editors and terminals found on this machine, the choices saved in
/// `state.json`, the folder opener and the crawl depth. Detection runs when the mode opens and after
/// a choice; nothing here throws for a missing program.
class SettingsState extends ChangeNotifier {
  SettingsState(this.session, {this.onDepth, Editors? editors, TerminalLauncher? terminals})
    : _editors = editors ?? session.editors,
      _terminals = terminals ?? session.terminals;

  bool _detected = false;

  /// The first time the mode opens: look for the editors and terminals (it starts processes, so not
  /// before anyone looks at Settings).
  Future<void> ensureDetected() async {
    if (_detected) return;
    _detected = true;
    await detect();
  }

  final Session session;
  final Editors _editors;
  final TerminalLauncher _terminals;

  /// Told when the crawl depth changes, so the next crawl uses it.
  final void Function(int depth)? onDepth;

  Prefs get _prefs => session.prefs;

  List<EditorOption> editors = const [];
  List<TerminalOption> terminals = const [];
  bool detecting = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Look for the editors and terminals again.
  Future<void> detect() async {
    detecting = true;
    notifyListeners();
    try {
      editors = await _editors.detect();
      terminals = await _terminals.detect();
    } finally {
      detecting = false;
      notifyListeners();
    }
  }

  // Editor ---------------------------------------------------------------------------------------

  /// The command saved in Settings, or null: the first detected editor is used.
  String? get savedEditor => _prefs.text(Settings.editorKey);

  /// The editor a file opens in now.
  EditorOption? get editorInUse => editors.isEmpty ? null : editors.first;

  /// Save [command] as the editor (null: back to detection) and look again.
  Future<void> chooseEditor(String? command) async {
    _prefs.setText(Settings.editorKey, command);
    await detect();
  }

  // Terminal and folders -------------------------------------------------------------------------

  String? get savedTerminal => _prefs.text(Settings.terminalKey);

  TerminalOption? get terminalInUse => TerminalLauncher.pick(terminals, savedTerminal);

  void chooseTerminal(String? id) {
    _prefs.setText(Settings.terminalKey, id);
    notifyListeners();
  }

  /// Folders open in the editor (when it can) instead of the file manager.
  bool get folderInEditor => _prefs.text(Settings.folderOpenerKey) == 'editor';

  void setFolderInEditor(bool value) {
    _prefs.setText(Settings.folderOpenerKey, value ? 'editor' : null);
    notifyListeners();
  }

  // Delete ---------------------------------------------------------------------------------------

  /// Delete into the trash (the default) rather than removing for good.
  bool get deleteToTrash => session.deleteToTrash;

  void setDeleteToTrash(bool value) {
    _prefs.setFlag(Settings.deleteToTrashFlag, value);
    notifyListeners();
  }

  /// Ask before deleting; off until chosen.
  bool get confirmDelete => session.confirmDelete;

  void setConfirmDelete(bool value) {
    _prefs.setFlag(Settings.confirmDeleteFlag, value);
    notifyListeners();
  }

  // Wheel ----------------------------------------------------------------------------------------

  /// Rows one Shift + wheel notch moves a list (2 to 1000, 5 until chosen).
  int get wheelStep => session.wheelStep;

  void setWheelStep(int rows) {
    final next = rows.clamp(Settings.wheelStepMin, Settings.wheelStepMax);
    if (next == wheelStep) return;
    _prefs.setNumber(Settings.wheelStepKey, next);
    notifyListeners();
  }

  /// Open `PLAN.md` in the editor in use, from the open repository when there is one; the error text,
  /// or null.
  Future<String?> testEditor() async {
    final root = session.repo?.root;
    try {
      await _editors.open(file: root == null ? 'PLAN.md' : '$root/PLAN.md');
      return null;
    } on EditorException catch (e) {
      return '$e';
    }
  }

  // Preview --------------------------------------------------------------------------------------

  /// Draw the first pages of a PDF in the Add and Ignore preview (takes effect when it is next opened).
  bool get renderPdf => _prefs.flag('previewPdf', fallback: false);

  void setRenderPdf(bool value) {
    _prefs.setFlag('previewPdf', value);
    notifyListeners();
  }

  // Crawl ----------------------------------------------------------------------------------------

  int get scanDepth => (_prefs.number(Settings.scanDepthKey) ?? RepoBrowser.depthDefault).clamp(RepoBrowser.depthMin, RepoBrowser.depthMax);

  void setScanDepth(int depth) {
    final next = depth.clamp(RepoBrowser.depthMin, RepoBrowser.depthMax);
    if (next == scanDepth) return;
    _prefs.setNumber(Settings.scanDepthKey, next);
    onDepth?.call(next);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
