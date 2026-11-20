import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/action_queue.dart';
import 'package:nvimos_poc/state/add_ignore.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/add_ignore_view.dart';
import 'package:nvimos_poc/ui/ignore_pane.dart';
import 'package:nvimos_poc/ui/preview_pane.dart';
import 'package:nvimos_poc/ui/side_pane.dart';
import 'package:nvimos_poc/ui/theme.dart';

Map<String, Object?> file(String path, {String index = ' ', String worktree = ' ', String kind = ''}) => {
  'path': path,
  'index': index,
  'worktree': worktree,
  'staged': kind == 'staged',
  'unstaged': kind == 'changed',
  'untracked': kind == 'untracked',
  'conflicted': kind == 'conflicted',
};

/// A state that records the actions it is asked for instead of running them.
class RecordingState extends AddIgnoreState {
  RecordingState(super.session);

  final calls = <String>[];

  @override
  Future<ActionResult> trackSelected() async {
    calls.add('track ${actionRows.map((r) => r.path).join(',')}');
    return const ActionResult('track', null);
  }

  @override
  Future<ActionResult> untrackSelected() async {
    calls.add('untrack ${actionRows.map((r) => r.path).join(',')}');
    return const ActionResult('untrack', null);
  }

  @override
  Future<ActionResult> deleteSelected() async {
    calls.add('delete ${actionRows.map((r) => r.path).join(',')}');
    return const ActionResult('delete', null);
  }
}

void main() {
  late Session session;
  late RecordingState state;

  setUp(() {
    session = Session();
    session.store.status = Status({
      'branch': 'main',
      'files': [
        file('clash.txt', index: 'U', worktree: 'U', kind: 'conflicted'),
        file('src/staged.txt', index: 'A', kind: 'staged'),
        file('src/changed.txt', worktree: 'M', kind: 'changed'),
        file('notes/new.txt', index: '?', worktree: '?', kind: 'untracked'),
        file('other.txt', index: '?', worktree: '?', kind: 'untracked'),
      ],
    });
    state = RecordingState(session);
  });

  tearDown(() {
    state.dispose();
    session.dispose();
  });

  Future<AddIgnoreViewState> mount(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      SessionScope(
        session: session,
        child: MaterialApp(theme: buildTheme(), home: Scaffold(body: AddIgnoreView(state: state))),
      ),
    );
    final view = t.state<AddIgnoreViewState>(find.byType(AddIgnoreView));
    view.focus.requestFocus();
    await t.pump();
    return view;
  }

  testWidgets('the list shows the four sections with their rows', (t) async {
    await mount(t);
    for (final s in ['Conflicts (1)', 'Staged (1)', 'Changed (1)', 'Untracked (2)']) {
      expect(find.text(s), findsOneWidget);
    }
    for (final n in ['clash.txt', 'staged.txt', 'changed.txt', 'new.txt', 'other.txt']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.text('5'), findsOneWidget, reason: 'the header counts the rows');
  });

  testWidgets('a right click on a row opens its menu: Open, Ignore…, Delete', (t) async {
    await mount(t);
    await t.tapAt(t.getCenter(find.text('new.txt')), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Ignore…'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the row buttons are always there, not only under the mouse', (t) async {
    await mount(t);
    expect(find.byIcon(Icons.add), findsNWidgets(3), reason: 'the changed row and the two untracked ones');
    expect(find.byIcon(Icons.remove), findsNWidgets(2), reason: 'the staged row and the changed one');
    expect(
      find.byIcon(Icons.visibility_off_outlined),
      findsNWidgets(4),
      reason: 'the eye on every row but the conflict: the staged, changed and two untracked ones',
    );
    expect(find.byIcon(Icons.delete_outline), findsNothing, reason: 'delete lives in the right-click menu');
  });

  testWidgets('arrows move the cursor, Shift+arrow and Ctrl+click highlight more rows', (t) async {
    await mount(t);
    expect(state.cursor, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    expect(state.cursor, 2);
    expect(state.selectionCount, 1);

    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(state.cursor, 4);
    expect([for (final r in state.selectedRows) r.path], ['src/changed.txt', 'notes/new.txt', 'other.txt']);

    await t.sendKeyEvent(LogicalKeyboardKey.escape); // back to the cursor row
    expect(state.selectionCount, 1);

    await t.tap(find.text('clash.txt'));
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.tap(find.text('staged.txt'));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect([for (final r in state.selectedRows) r.path], ['clash.txt', 'src/staged.txt']);

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyA);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(state.selectionCount, 5);
  });

  testWidgets('the keys t and u ask the state to add or untrack the highlighted rows', (t) async {
    await mount(t);
    state.click(3); // notes/new.txt
    state.click(4, shift: true); // .. other.txt
    await t.sendKeyEvent(LogicalKeyboardKey.keyT);
    await t.sendKeyEvent(LogicalKeyboardKey.keyU);
    await t.pump();
    expect(state.calls, ['track notes/new.txt,other.txt', 'untrack notes/new.txt,other.txt']);
  });

  testWidgets('the filter narrows the rows, Esc clears it, / and the list keys do not mix', (t) async {
    final view = await mount(t);
    await t.sendKeyEvent(LogicalKeyboardKey.slash);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'add and ignore filter');
    await t.enterText(find.byType(TextField), 'new');
    await t.pump();
    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('other.txt'), findsNothing);
    expect(find.text('CONFLICTS  1'), findsNothing);

    await t.sendKeyEvent(LogicalKeyboardKey.escape); // out of the field, back to the list
    await t.pump();
    expect(FocusManager.instance.primaryFocus, view.focus);
    await t.sendKeyEvent(LogicalKeyboardKey.escape); // clears the filter
    await t.pump();
    expect(find.text('other.txt'), findsOneWidget);
  });

  testWidgets("a row's actions are always there, each with a tooltip", (t) async {
    await mount(t);
    for (final tip in ['Add: stage the whole file (t)', 'Untrack: take it out of the index (u)']) {
      expect(find.byTooltip(tip), findsWidgets);
    }
    expect(
      find.byTooltip('Ignore: add the literal path to the project .gitignore (I; i or right-click to choose)'),
      findsNWidgets(2),
      reason: 'the eye is on the untracked rows only',
    );
    expect(find.byTooltip(RegExp('Delete')), findsNothing, reason: 'delete is in the right-click menu');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('hovering a state letter explains what it means on its side', (t) async {
    await mount(t);
    for (final tip in [
      'Unmerged: a conflict is waiting to be resolved',
      'Added: staged in the index, ready to commit',
      'Modified: in the working tree, not staged yet',
      'Untracked: git does not track this path yet',
    ]) {
      expect(find.byTooltip(tip), findsWidgets);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('p and v show one pane at a time, the view is remembered, and the width is kept', (t) async {
    await mount(t);
    expect(find.byType(SidePane), findsOneWidget, reason: 'the pane is open, as in Purrage');
    expect(find.byType(IgnorePane), findsOneWidget, reason: 'the ignore rules until another view is asked');

    await t.sendKeyEvent(LogicalKeyboardKey.keyV); // the one pane switches to the preview
    await t.pump();
    expect(find.byType(IgnorePane), findsNothing);
    expect(find.byType(PreviewPane), findsOneWidget);
    expect(session.prefs.text(Settings.sideViewKey), 'preview');

    await t.sendKeyEvent(LogicalKeyboardKey.keyV); // the same key again hides it
    await t.pump();
    expect(find.byType(SidePane), findsNothing);

    await t.sendKeyEvent(LogicalKeyboardKey.keyP); // p shows it on the rules
    await t.pump();
    expect(find.byType(IgnorePane), findsOneWidget);
    expect(session.prefs.text(Settings.sideViewKey), 'ignore');

    // The visible switch above the pane picks the same views.
    await t.tap(find.byTooltip('The highlighted files (v)'));
    await t.pump();
    expect(find.byType(PreviewPane), findsOneWidget);
    expect(session.prefs.text(Settings.sideViewKey), 'preview');
    await t.tap(find.byTooltip('The .gitignore files and their lines (p)'));
    await t.pump();
    expect(find.byType(IgnorePane), findsOneWidget);
    expect(session.prefs.text(Settings.sideViewKey), 'ignore');

    // The remembered view and the width a drag leaves are both restored next run.
    session.prefs.setText(Settings.sideViewKey, 'preview');
    session.prefs.setNumber(Settings.sidePaneWidthKey, 420);
    await t.pumpWidget(const SizedBox.shrink());
    await mount(t);
    expect(find.byType(PreviewPane), findsOneWidget, reason: 'the remembered view, not the default');
    expect(t.widget<SidePane>(find.byType(SidePane)).width.value, 420);
  });

  testWidgets('dragging the pane edge resizes without rebuilding the list or the pane', (t) async {
    await mount(t);
    final pane = t.widget(find.byType(IgnorePane));
    final filter = t.widget(find.byType(TextField));
    final before = t.getSize(find.byType(IgnorePane)).width;
    final edge = find.descendant(
      of: find.byType(SidePane),
      matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onHorizontalDragUpdate != null),
    );
    await t.drag(edge, const Offset(-60, 0));
    await t.pump(const Duration(milliseconds: 400)); // past the edge's double-tap timer
    expect(t.getSize(find.byType(IgnorePane)).width, greaterThan(before), reason: 'dragged left, the pane grows');
    expect(identical(t.widget(find.byType(IgnorePane)), pane), isTrue, reason: 'the pane is not rebuilt');
    expect(identical(t.widget(find.byType(TextField)), filter), isTrue, reason: 'the list column is not rebuilt');
  });

  testWidgets('the pane edge stays under the pointer, also with several moves in one frame', (t) async {
    await mount(t);
    final before = t.getSize(find.byType(IgnorePane)).width;
    final edge = find.descendant(
      of: find.byType(SidePane),
      matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onHorizontalDragUpdate != null),
    );
    final g = await t.startGesture(t.getCenter(edge), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-10, 0)); // no pump between: the events of one frame
    }
    await t.pump();
    expect(t.getSize(find.byType(IgnorePane)).width, before + 60, reason: 'every move counts');
    await g.moveBy(const Offset(25, 0));
    await t.pump();
    expect(t.getSize(find.byType(IgnorePane)).width, before + 35);
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('under 600 px the pane starts hidden; p opens it for the session and a resize keeps it', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(500, 700);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      SessionScope(
        session: session,
        child: MaterialApp(theme: buildTheme(), home: Scaffold(body: AddIgnoreView(state: state))),
      ),
    );
    final view = t.state<AddIgnoreViewState>(find.byType(AddIgnoreView));
    view.focus.requestFocus();
    await t.pump();
    expect(MediaQuery.sizeOf(t.element(find.byType(AddIgnoreView))).width, 500);
    expect(find.byType(SidePane), findsNothing, reason: 'hidden by default under 600 px');

    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.pump();
    expect(find.byType(SidePane), findsOneWidget, reason: 'p still opens it under 600 px');

    t.view.physicalSize = const Size(1000, 700);
    await t.pump();
    expect(find.byType(SidePane), findsOneWidget, reason: 'a later resize does not undo the choice');

    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.pump();
    expect(find.byType(SidePane), findsNothing);
  });

  testWidgets('delete asks only when Settings says so; the default deletes at once', (t) async {
    await mount(t);
    await t.sendKeyEvent(LogicalKeyboardKey.keyX);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: 'no question unless Settings asks');
    expect(state.calls.single, startsWith('delete '));

    session.prefs.setFlag(Settings.confirmDeleteFlag, true);
    await t.sendKeyEvent(LogicalKeyboardKey.keyX);
    await t.pumpAndSettle();
    expect(find.text('Move to the trash?'), findsOneWidget);
    await t.tap(find.text('Move to trash'));
    await t.pumpAndSettle();
    expect(state.calls.length, 2);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
