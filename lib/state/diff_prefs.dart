import 'package:flutter/widgets.dart';

/// Unified or side-by-side diff.
enum DiffLayout { unified, sideBySide }

/// How diffs are shown, the same in Pull request and Changes; for this session only.
class DiffPrefs extends ChangeNotifier {
  DiffLayout layout = DiffLayout.unified;

  /// Long lines wrap; off: they stay on one line.
  bool wrap = true;

  void toggleLayout() => setLayout(layout == DiffLayout.unified ? DiffLayout.sideBySide : DiffLayout.unified);

  void setLayout(DiffLayout l) {
    layout = l;
    notifyListeners();
  }

  void toggleWrap() {
    wrap = !wrap;
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
