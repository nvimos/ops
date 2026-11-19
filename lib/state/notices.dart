import 'dart:async';

import 'package:flutter/foundation.dart';

/// One message in the notice bar. [detail] is the full text behind it (the trace, with Neovim's or
/// git's own words); [count] says how many times the same message came in a row.
class Notice {
  const Notice(this.message, {this.detail, this.failure = true, this.count = 1});

  final String message;
  final String? detail;

  /// A failure is drawn in the error colours.
  final bool failure;
  final int count;

  /// There is more to read than the message: the Details button opens it.
  bool get hasDetail => detail != null && detail!.trim() != message.trim();
}

/// The notice the UI shows, and when it goes away: on its own after [lifetime], except while the mouse
/// is over it: hovering holds it, leaving starts the countdown again with the time that was left.
/// The same message again (a failing action tried twice) is one notice with a count, not a second one.
///
/// Deliberately not a SnackBar: a failure has to stay readable while the user looks at the row it
/// concerns, not vanish wherever the pointer happens to be.
class Notices extends ChangeNotifier {
  Notices({this.lifetime = const Duration(seconds: 6)});

  final Duration lifetime;

  Notice? _current;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  DateTime? _timerStart;
  bool _hovered = false;
  bool _disposed = false;

  Notice? get current => _current;
  bool get hovered => _hovered;

  /// Show [message]; the same message as the one up groups with it (its count goes up).
  void show(String message, {String? detail, bool failure = true}) {
    final again = _current?.message == message && _current?.failure == failure;
    _current = Notice(message, detail: detail, failure: failure, count: again ? _current!.count + 1 : 1);
    _remaining = lifetime;
    _timerStart = null;
    _timer?.cancel();
    _startTimer();
    notifyListeners();
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _timerStart = null;
    if (_current == null) return;
    _current = null;
    _hovered = false;
    notifyListeners();
  }

  /// The pointer entered or left the notice.
  void setHovered(bool value) {
    if (_hovered == value) return;
    if (value) {
      _rememberRemaining();
      _timer?.cancel();
      _timer = null;
    }
    _hovered = value;
    if (!value) _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    if (_current == null || _hovered || _remaining <= Duration.zero) return;
    _timer?.cancel();
    _timerStart = DateTime.now();
    _timer = Timer(_remaining, dismiss);
  }

  /// Keep what is left, so leaving and re-entering does not reset the clock.
  void _rememberRemaining() {
    final start = _timerStart;
    if (start == null) return;
    final left = _remaining - DateTime.now().difference(start);
    _remaining = left.isNegative ? Duration.zero : left;
    _timerStart = null;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
