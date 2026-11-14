import 'package:flutter/widgets.dart';

import 'prefs.dart';

/// Unified or side-by-side diff.
enum DiffLayout { unified, sideBySide }

/// How diffs are shown, the same in Pull request and Changes. The layout is for this session only;
/// wrapping and the hunk headers are kept in [Prefs] (the app's state file) between runs.
class DiffPrefs extends ChangeNotifier {
  DiffPrefs(this._prefs)
    : wrap = _prefs.flag('diffWrap', fallback: true),
      hunkHeaders = _prefs.flag('hunkHeaders', fallback: true);

  final Prefs _prefs;

  DiffLayout layout = DiffLayout.unified;

  /// Long lines wrap; off: they stay on one line.
  bool wrap;

  /// The header above each hunk (lines, counts, section); off: the code runs on without a gap.
  bool hunkHeaders;

  void toggleHunkHeaders() {
    hunkHeaders = !hunkHeaders;
    _prefs.setFlag('hunkHeaders', hunkHeaders);
    notifyListeners();
  }

  void toggleLayout() => setLayout(layout == DiffLayout.unified ? DiffLayout.sideBySide : DiffLayout.unified);

  void setLayout(DiffLayout l) {
    layout = l;
    notifyListeners();
  }

  void toggleWrap() {
    wrap = !wrap;
    _prefs.setFlag('diffWrap', wrap);
    notifyListeners();
  }
}

/// The scroll position of a diff, which Up / Down move DiffScroll.step lines at a time.
class DiffScroll extends ScrollController {
  /// A rough height of a diff line; wrapped lines are taller, so this is a step, not a count.
  static const lineHeight = 18.0;

  /// Lines one Up / Down press scrolls.
  static const step = 3;

  /// Lines one Shift+Up / Shift+Down press scrolls.
  static const bigStep = 10;

  /// Scroll [lines] down (up for a negative number), stopping at the ends.
  void byLines(int lines) {
    if (!hasClients) return;
    final p = position;
    jumpTo((p.pixels + lines * lineHeight).clamp(p.minScrollExtent, p.maxScrollExtent));
  }
}
