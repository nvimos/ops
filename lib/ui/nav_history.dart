import 'package:material_ui/material_ui.dart';

/// A place to come back to: what it is called and how to show it again.
class NavPlace {
  const NavPlace(this.label, this.show);

  /// For the debug bar, e.g. `TASK-198` or `Back to Tasks`.
  final String label;

  /// Put that place back on screen.
  final VoidCallback show;
}

/// The app's back stack. A jump pushes where the user was; the mouse's back button pops it.
///
/// A place is a restore, not a route: the modes stay alive, so going back puts the right mode and
/// its task selection back without rebuilding anything from scratch.
class NavHistory {
  /// Deep enough for a session's trail; the oldest place falls off.
  static const maxDepth = 50;

  final _back = <NavPlace>[];

  bool get canGoBack => _back.isNotEmpty;

  /// What the back button would show; for the debug bar.
  String? get label => _back.isEmpty ? null : _back.last.label;

  void push(NavPlace place) {
    _back.add(place);
    if (_back.length > maxDepth) _back.removeAt(0);
  }

  /// Show the previous place; false when there is none.
  bool back() {
    if (_back.isEmpty) return false;
    _back.removeLast().show();
    return true;
  }

  void clear() => _back.clear();
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
