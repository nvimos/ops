import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'input_modality.dart';
import 'theme.dart';

/// A row that highlights on hover and when selected; the basic list item everywhere.
class HoverRow extends StatefulWidget {
  const HoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.pointer = true,
    this.selectedColor = C.surface2,
    this.bar,
    this.onContextMenu,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// A right click, with where it happened (screen coordinates), for the row's menu.
  final ValueChanged<Offset>? onContextMenu;

  /// The background of a selected row; a row on a [C.surface2] box (a drop-down) needs another one.
  final Color selectedColor;

  /// A 3 px bar down the left edge: the current or active row (`C.accent`). Pass a transparent one on
  /// the rows without it, so their content stays lined up with it.
  final Color? bar;

  /// Show the pointing hand over a clickable row; off for rows whose clickability is obvious (files).
  final bool pointer;
  final bool selected;
  final EdgeInsets padding;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

/// Tells what is inside a [HoverRow] whether the mouse is over the row, so a button in it can show
/// only then. Without a row around, or without a mouse (touch), [of] says true: nothing is hidden.
class RowHover extends InheritedWidget {
  const RowHover({super.key, required this.hovered, required super.child});

  final bool hovered;

  static bool _touchOnly() =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  static bool of(BuildContext context) {
    final row = context.dependOnInheritedWidgetOfExactType<RowHover>();
    return row == null || row.hovered || _touchOnly();
  }

  @override
  bool updateShouldNotify(RowHover old) => hovered != old.hovered;
}

class _HoverRowState extends State<HoverRow> {
  /// The pointer is over the row, whether or not it is allowed to show it (see [InputModality]).
  bool _hover = false;

  /// The hover look belongs to the pointer: after a key press it waits for the mouse to move, so
  /// the row that scrolls under a resting mouse does not light up and read as the focused one.
  bool get _hoverShown => _hover && InputModality.instance.isPointer;

  MouseCursor get _cursor =>
      widget.onTap != null && widget.pointer ? SystemMouseCursors.click : MouseCursor.defer;

  GestureTapUpCallback? get _secondaryTapUp =>
      widget.onContextMenu == null ? null : _secondaryTap;

  void _secondaryTap(TapUpDetails details) => widget.onContextMenu!(details.globalPosition);

  void _pointerEntered(PointerEnterEvent _) => setState(() => _hover = true);

  void _pointerExited(PointerExitEvent _) => setState(() => _hover = false);

  // Only a real movement says the pointer is in use: entering because the list scrolled under it
  // does not.
  void _pointerHovered(PointerHoverEvent _) => InputModality.instance.pointerUsed();

  void _pointerDown(TapDownDetails _) => InputModality.instance.pointerUsed();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: InputModality.instance,
    builder: (context, _) => _row(),
  );

  Widget _row() {
    final hover = RowHover(hovered: _hoverShown, child: _content(hovered: _hoverShown));
    final gestures = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _pointerDown,
      onTap: widget.onTap,
      onSecondaryTapUp: _secondaryTapUp,
      child: hover,
    );
    return MouseRegion(
      cursor: _cursor,
      onEnter: _pointerEntered,
      onHover: _pointerHovered,
      onExit: _pointerExited,
      child: gestures,
    );
  }

  Widget _content({required bool hovered}) => Container(
    decoration: _decoration(hovered: hovered),
    padding: widget.padding,
    child: widget.child,
  );

  BoxDecoration _decoration({required bool hovered}) {
    final background = widget.selected ? widget.selectedColor : (hovered ? C.hover : Colors.transparent);
    final bar = widget.bar;
    final border = bar == null ? null : Border(left: BorderSide(width: 3, color: bar));
    return BoxDecoration(color: background, border: border);
  }
}

/// A small rounded label: status, Added/Modified/Removed, counts.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = C.muted, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: filled ? C.bg : color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// A compact flat button.
class SmallButton extends StatelessWidget {
  const SmallButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.primary = false,
    this.danger = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool danger;

  /// Has the keyboard when its dialog opens, so Enter and Space press it.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? C.red : (primary ? C.bg : C.text);
    final bg = primary ? C.accent : C.surface2;
    return TextButton(
      onPressed: onPressed,
      autofocus: autofocus,
      style: TextButton.styleFrom(
        backgroundColor: onPressed == null ? C.surface : bg,
        foregroundColor: fg,
        disabledForegroundColor: C.faint,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: BorderSide(color: primary ? C.accent : C.border),
        ),
        textStyle: const TextStyle(fontSize: 12.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 5)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// A header bar for a pane.
class PaneHeader extends StatelessWidget {
  const PaneHeader({super.key, required this.title, this.trailing = const []});

  final Widget title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle(style: T.title, overflow: TextOverflow.ellipsis, child: title),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// Centered muted text for empty states.
class Empty extends StatelessWidget {
  const Empty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, style: T.small, textAlign: TextAlign.center),
    ),
  );
}

/// A small progress circle for "loading" and "running".
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(strokeWidth: 1.5),
  );
}

/// An x at the right edge of a search field, shown while it has text; a click clears the field and
/// reports the empty text, as typing would.
/// Nothing is left of the cursor in the field: it is empty, or the cursor is at its start.
bool cursorAtStart(TextEditingController c) => c.selection.isCollapsed && c.selection.baseOffset <= 0;

/// Alt+X in the [child] text field empties it, like its clear button, and calls [onCleared] so the
/// list it filters is refreshed with the filter gone.
class ClearOnAltX extends StatelessWidget {
  const ClearOnAltX({super.key, required this.controller, required this.onCleared, required this.child});

  final TextEditingController controller;
  final ValueChanged<String> onCleared;
  final Widget child;

  void _clear() {
    controller.clear();
    onCleared('');
  }

  @override
  Widget build(BuildContext context) =>
      CallbackShortcuts(bindings: {const SingleActivator(LogicalKeyboardKey.keyX, alt: true): _clear}, child: child);
}

class ClearButton extends StatelessWidget {
  const ClearButton({super.key, required this.controller, required this.onCleared});

  final TextEditingController controller;
  final ValueChanged<String> onCleared;

  /// For InputDecoration.suffixIconConstraints, so the x doesn't make the field taller.
  static const constraints = BoxConstraints(minWidth: 26, minHeight: 20);

  void _clear() {
    controller.clear();
    onCleared('');
  }

  /// One semantics node of its own, whether the x shows or not: the x appearing with the first letter
  /// would otherwise reshape the field's node, and on Windows the field loses the keyboard (see
  /// `_FieldButtons` in `changes_view.dart`).
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) => v.text.isEmpty
          ? const SizedBox.shrink()
          : Tooltip(
              message: 'Clear',
              child: InkWell(
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(8),
                onTap: _clear,
                child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: C.muted)),
              ),
            ),
    ),
  );
}

/// A small icon button with its tooltip and the pointing hand: the row actions of a list. The
/// icon is the whole target; a disabled one ([onPressed] null) keeps the plain cursor.
class IconAction extends StatelessWidget {
  const IconAction({super.key, required this.icon, required this.tooltip, required this.onPressed, this.color = C.muted});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: MouseRegion(
      cursor: onPressed == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: SelectionContainer.disabled(child: Icon(icon, size: 15, color: onPressed == null ? C.faint : color)),
        ),
      ),
    ),
  );
}
