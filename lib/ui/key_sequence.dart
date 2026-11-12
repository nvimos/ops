import 'dart:async';

/// Vim-style key commands: single keys ("v"), sequences ("gs", "]f") and sequences with a count
/// ("2gi"), the keys typed within a second of each other. [press] returns whether the key was used
/// (the start of a longer sequence is).
class KeySequence {
  KeySequence(this.commands, {this.timeout = const Duration(seconds: 1)});

  /// Command keys -> action. A command is one or more characters.
  final Map<String, void Function()> commands;
  final Duration timeout;

  String _typed = '';
  Timer? _timer;

  bool press(String? ch) {
    if (ch == null || ch.isEmpty) return false;
    final seq = _typed + ch;
    _clear();
    if (commands.keys.any((c) => c.length > seq.length && c.startsWith(seq))) {
      _typed = seq;
      _timer = Timer(timeout, _clear);
      return true;
    }
    final action = commands[seq];
    action?.call();
    return action != null;
  }

  /// The start of a longer sequence was typed: the next key belongs to it (the `w` of `zw`).
  bool get pending => _typed.isNotEmpty;

  void _clear() {
    _timer?.cancel();
    _typed = '';
  }

  void dispose() => _clear();
}
