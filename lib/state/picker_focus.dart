import 'package:flutter/widgets.dart';

/// The focus of a branch picker: the field, or one of the items of the list under it. The list is
/// an overlay, so its items are not under the field in the focus tree; [hasFocus] is therefore true
/// for the picker while the focus is on one of its items too, so the picker still reads as focused
/// (the shell's keys, Tab, the pane moves) while the keyboard is in its list.
class PickerFocusNode extends FocusNode {
  PickerFocusNode({super.debugLabel});

  /// Whether one of the list's items has the focus; set by the picker that shows the list.
  bool Function()? listHasFocus;

  @override
  bool get hasFocus => super.hasFocus || (listHasFocus?.call() ?? false);
}
