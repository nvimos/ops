import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../rpc/client.dart';
import 'theme.dart';
import 'widgets.dart';

/// The first line a person needs from an error text: no `NvimError(...)` / `Lua:` prefixes,
/// no stack traceback.
String shortError(String full) => NvimError.shorten(full.replaceFirst(RegExp(r'^NvimError\([^)]*\):\s*'), ''));

/// An error in place of a view: the short message, then the full text with the trace,
/// all selectable, and a Copy button.
class ErrorPane extends StatelessWidget {
  const ErrorPane(this.text, {super.key, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final short = shortError(text);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.error_outline, size: 16, color: C.red),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(short, style: T.title)),
                const SizedBox(width: 8),
                SmallButton('Copy', icon: Icons.copy, onPressed: () => Clipboard.setData(ClipboardData(text: text))),
                if (onRetry != null) ...[const SizedBox(width: 6), SmallButton('Retry', onPressed: onRetry)],
              ],
            ),
            if (text.trim() != short) ...[
              const SizedBox(height: 12),
              Text(text, style: T.code.copyWith(color: C.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Show an action's error (null: nothing) as a short snackbar with a Details link to the full,
/// selectable text. A plain message (nothing more to show) gets no Details link.
void showActionError(BuildContext context, String? err) {
  if (err == null || !context.mounted) return;
  final short = shortError(err);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(short),
      duration: const Duration(seconds: 6),
      action: short == err.trim()
          ? null
          : SnackBarAction(label: 'Details', onPressed: () => showErrorDetails(context, err)),
    ),
  );
}

/// A short note that the app did something by itself, with Undo. It goes away after [shownFor],
/// or, when the mouse is over it then, as soon as the mouse leaves.
void showAutoStatus(
  BuildContext context,
  String text, {
  required VoidCallback onUndo,
  Duration shownFor = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> shown;
  shown = messenger.showSnackBar(
    SnackBar(
      padding: EdgeInsets.zero,
      duration: const Duration(days: 1), // the note closes itself, see HoverDismiss
      content: HoverDismiss(
        after: shownFor,
        onDismiss: () => shown.close(),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            TextButton(
              onPressed: () {
                shown.close();
                onUndo();
              },
              child: const Text('Undo'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Calls [onDismiss] [after] a delay, but not while the mouse is over [child]: then it waits
/// until the mouse leaves.
class HoverDismiss extends StatefulWidget {
  const HoverDismiss({super.key, required this.after, required this.onDismiss, required this.child});

  final Duration after;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<HoverDismiss> createState() => _HoverDismissState();
}

class _HoverDismissState extends State<HoverDismiss> {
  late final Timer _timer = Timer(widget.after, _elapsed);
  bool _hover = false;
  bool _due = false;

  @override
  void initState() {
    super.initState();
    _timer; // start the clock
  }

  void _elapsed() {
    _due = true;
    if (!_hover) widget.onDismiss();
  }

  void _hovering(bool on) {
    _hover = on;
    if (!on && _due) widget.onDismiss();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _hovering(true),
    onExit: (_) => _hovering(false),
    child: Padding(padding: const EdgeInsets.only(left: 24, right: 8), child: widget.child),
  );
}

Future<void> showErrorDetails(BuildContext context, String err) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    backgroundColor: C.surface,
    contentPadding: EdgeInsets.zero,
    content: SizedBox(width: 680, height: 420, child: ErrorPane(err)),
    actions: [SmallButton('Close', onPressed: () => Navigator.pop(c))],
  ),
);
