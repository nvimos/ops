import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/action_queue.dart';
import 'package:nvimos_poc/state/add_ignore.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/add_ignore_view.dart';
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
    for (final s in ['CONFLICTS  1', 'STAGED  1', 'CHANGED  1', 'UNTRACKED  2']) {
      expect(find.text(s), findsOneWidget);
    }
    for (final n in ['clash.txt', 'staged.txt', 'changed.txt', 'new.txt', 'other.txt']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.text('5'), findsOneWidget, reason: 'the header counts the rows');
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

  testWidgets('a row has its actions on hover, each with a tooltip', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows; // a touch platform shows them all the time
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await mount(t);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.text('new.txt')));
    await t.pump();
    for (final tip in ['Add: stage the whole file (t)', 'Ignore: add a rule to .gitignore (i)', 'Delete: move to the trash (x)']) {
      expect(find.byTooltip(tip), findsOneWidget);
    }
    expect(find.byTooltip('Untrack: take it out of the index (u)'), findsNothing, reason: 'an untracked file has nothing to untrack');
  });
}
