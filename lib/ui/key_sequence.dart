import 'dart:async';

/// Vim-style key commands: single keys ("v") and two-key sequences ("gs", "]f") typed within a
/// second of each other. [press] returns whether the key was used (a sequence's first key is).
class KeySequence {
  KeySequence(this.commands, {this.timeout = const Duration(seconds: 1)});

  /// Command keys -> action. Keys are one or two characters.
  final Map<String, void Function()> commands;
  final Duration timeout;

  String? _prefix;
  Timer? _timer;

  bool press(String? ch) {
    if (ch == null || ch.isEmpty) return false;
    final p = _prefix;
    _clear();
    if (p != null) {
      final action = commands['$p$ch'];
      action?.call();
      return action != null;
    }
    if (commands.keys.any((k) => k.length == 2 && k[0] == ch)) {
      _prefix = ch;
      _timer = Timer(timeout, _clear);
      return true;
    }
    final action = commands[ch];
    action?.call();
    return action != null;
  }

  void _clear() {
    _timer?.cancel();
    _prefix = null;
  }

  void dispose() => _clear();
}
