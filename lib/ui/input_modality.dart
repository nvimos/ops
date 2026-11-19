import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which device drove the interface last: the pointer or the keyboard.
///
/// This is the UI world's *input-modality-aware hover* (the name Zed's GPUI uses; browsers keep the same
/// rule by deferring `:hover` updates while a scroll runs, and `:focus-visible` is the matching rule for
/// focus rings): a hover look belongs to the pointer, so a key press suppresses it until the pointer is
/// used again. Without it, the row that slides under a resting mouse while the keys scroll gets a hover
/// highlight and looks like the one the keys are on.
///
/// [instance] is the one record. [HoverRow] asks [isPointer] before it paints; the window feeds it the
/// keyboard through [watch], and every mouse move or press through [pointerUsed].
class InputModality extends ChangeNotifier {
  InputModality();

  static final InputModality instance = InputModality();

  bool _pointer = true;

  /// The pointer was the last device: hover shows.
  bool get isPointer => _pointer;

  /// The keyboard was the last device: hover stays hidden until the pointer moves or a button goes
  /// down again.
  bool get isKeyboard => !_pointer;

  /// A mouse move or a button press: hover shows from now on.
  void pointerUsed() => _set(true);

  /// A key went down: hover hides until the pointer is used again.
  void keyboardUsed() => _set(false);

  void _set(bool pointer) {
    if (_pointer == pointer) return;
    _pointer = pointer;
    notifyListeners();
  }

  /// Listen to the window's keyboard: any key down (or a held key repeating) makes the keyboard the
  /// device in use. Returns the function that stops listening, for an owner that goes away.
  VoidCallback watch() {
    bool onKey(KeyEvent event) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) keyboardUsed();
      return false; // never claim the key: the handlers still see it
    }

    HardwareKeyboard.instance.addHandler(onKey);
    return () => HardwareKeyboard.instance.removeHandler(onKey);
  }

  /// Back to the pointer, for a test that sent keys.
  void reset() => _set(true);
}
