import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Shows every tooltip on screen, one at a time, and expects its bubble in the semantics tree.
///
/// Why: on desktop a tooltip's bubble lives in the root overlay and Flutter grafts its semantics
/// node under the tooltip's owner (`OverlayPortal`, `traversalParentIdentifier`). When two tooltips
/// (or other overlay portals) merge into one semantics node, the merge keeps only the first one's
/// identifier (`SemanticsConfiguration.absorb`, Flutter 3.50), so the other bubble has no parent.
/// It is still sent, and the Windows accessibility bridge logs
/// `Failed to update ui::AXTree, error: <id> will not be in the tree and is not the new root` on
/// every frame of its fade. The fix is to give that tooltip its own node (`Semantics(container: true)`
/// around it).
///
/// [skip] names messages that are known to be fine elsewhere or not worth showing.
Future<void> expectTooltipsInSemantics(WidgetTester t, {Set<String> skip = const {}}) async {
  final handle = t.ensureSemantics();
  try {
    await t.pump();
    final missing = <String>[];
    final tooltips = find.byType(Tooltip).evaluate().toList();
    expect(tooltips, isNotEmpty, reason: 'the screen has tooltips to check');
    for (final element in tooltips) {
      if (!element.mounted) continue;
      final tooltip = element.widget as Tooltip;
      final message = tooltip.message ?? tooltip.richMessage?.toPlainText() ?? '';
      if (message.isEmpty || skip.contains(message)) continue;
      final state = (element as StatefulElement).state as TooltipState;
      if (!state.ensureTooltipVisible()) continue;
      await t.pump(const Duration(milliseconds: 200));
      if (orphanOverlayNodes(t).isNotEmpty) missing.add(message);
      Tooltip.dismissAllToolTips();
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(missing, isEmpty, reason: 'these tooltip bubbles are not in the semantics tree; give each '
        'tooltip its own node (Semantics(container: true)) so it does not merge with another one');
  } finally {
    handle.dispose();
  }
}

/// The overlay children (a shown tooltip's bubble, a menu) that are attached to the semantics tree
/// but cannot be reached from the root in traversal order, the order the engine builds the platform
/// tree from: the nodes the Windows bridge rejects.
List<SemanticsNode> orphanOverlayNodes(WidgetTester t) {
  final root = t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  final attached = <SemanticsNode>[];
  void collect(SemanticsNode node) {
    if (node.getSemanticsData().traversalChildIdentifier != null) attached.add(node);
    node.visitChildren((child) {
      collect(child);
      return true;
    });
  }

  final reachable = <SemanticsNode>{};
  void walk(SemanticsNode node) {
    reachable.add(node);
    node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder).forEach(walk);
  }

  collect(root);
  walk(root);
  return attached.where((n) => !reachable.contains(n)).toList();
}
