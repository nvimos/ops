import 'package:material_ui/material_ui.dart';

/// A place to come back to: what it is called and how to show it again.
class NavPlace {
  const NavPlace(this.label, this.show);

  /// For the debug bar, e.g. `TASK-198` or `Back to Tasks`.
  final String label;

  /// Put that place back on screen.
  final VoidCallback show;
}

/// One jump: where the user came [from], and, when the jump can be repeated, where it went [to].
class _Jump {
  const _Jump(this.from, this.to);

  final NavPlace from;
  final NavPlace? to;
}

/// The app's back and forward stacks, like a browser's. A jump pushes where the user was; the
/// mouse's back button returns there, and its forward button repeats the jump.
///
/// A place is a restore, not a route: the modes stay alive, so going back puts the right mode and
/// its task selection back without rebuilding anything from scratch. Notifies so the debug bar
/// follows the stacks live.
class NavHistory extends ChangeNotifier {
  /// Deep enough for a session's trail; the oldest place falls off.
  static const maxDepth = 50;

  final _back = <_Jump>[];
  final _forward = <_Jump>[];

  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  /// What the back button would show; for the debug bar.
  String? get label => _back.isEmpty ? null : _back.last.from.label;

  /// What the forward button would show.
  String? get forwardLabel => _forward.isEmpty ? null : _forward.last.to!.label;

  /// Record a jump away from [place]. With [to] (how to show where the jump went), back can be
  /// undone with forward; without it the jump is back-only. A new jump drops the forward trail.
  void push(NavPlace place, {NavPlace? to}) {
    _back.add(_Jump(place, to));
    if (_back.length > maxDepth) _back.removeAt(0);
    _forward.clear();
    notifyListeners();
  }

  /// Show the previous place; false when there is none.
  bool back() {
    if (_back.isEmpty) return false;
    final jump = _back.removeLast();
    if (jump.to != null) _forward.add(jump);
    jump.from.show();
    notifyListeners();
    return true;
  }

  /// Repeat the jump the last back undid; false when there is none.
  bool forward() {
    if (_forward.isEmpty) return false;
    final jump = _forward.removeLast();
    _back.add(jump);
    jump.to!.show();
    notifyListeners();
    return true;
  }

  void clear() {
    if (_back.isEmpty && _forward.isEmpty) return;
    _back.clear();
    _forward.clear();
    notifyListeners();
  }
}

/// The shell's [NavHistory] for everything under it: an action that jumps somewhere else records
/// where the user came from first, so the mouse's back button knows the way home.
class NavScope extends InheritedWidget {
  const NavScope({super.key, required this.history, required super.child});

  final NavHistory history;

  /// Null when a view is used on its own (tests, a preview): there is no back button to feed.
  static NavHistory? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<NavScope>()?.history;

  @override
  bool updateShouldNotify(NavScope old) => history != old.history;
}
