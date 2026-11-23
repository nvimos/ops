import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/commit_template.dart';
import 'package:nvimos_poc/ui/changes_view.dart';
import 'package:nvimos_poc/ui/commit_message_dialog.dart';
import 'package:nvimos_poc/ui/nav_keys.dart' show NavDir;
import 'package:nvimos_poc/ui/theme.dart';
import 'support/semantics_focus.dart';
import 'support/tooltip_semantics.dart';

Status status() => Status({
  'branch': 'main',
  'files': [
    {'path': 'a.txt', 'index': 'M', 'worktree': ' ', 'staged': true},
    {'path': 'new.txt', 'index': 'A', 'worktree': ' ', 'staged': true},
    {'path': 'b.txt', 'index': ' ', 'worktree': 'M', 'unstaged': true},
    {'path': 'x.tmp', 'index': '?', 'worktree': '?', 'untracked': true, 'unstaged': true},
  ],
});

void main() {
  test('the template lists the files as git does, every line a comment', () {
    final t = gitCommitTemplate(status());
    expect(t.split('\n').every((l) => l.startsWith('#')), isTrue);
    expect(t, contains('# On branch main'));
    expect(t, contains('# Changes to be committed:\n#\tmodified:   a.txt\n#\tnew file:   new.txt'));
    expect(t, contains('# Changes not staged for commit:\n#\tmodified:   b.txt'));
    expect(t, contains('# Untracked files:\n#\tx.tmp'));
  });

  test('comment lines are dropped from the edited message', () {
    expect(stripCommitComments('fix it\n\nwhy\n\n# comment\n#\tmodified: a\n'), 'fix it\n\nwhy');
    expect(stripCommitComments('\n# only comments\n'), '');
  });

  testWidgets('the field has an X that clears it (only with text) and a button for the large window', (t) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    var expanded = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: CommitBox(
            controller: controller,
            focus: focus,
            onExpand: () => expanded++,
            label: 'Commit',
            enabled: true,
            onCommit: () {},
            onLeave: () {},
            onTab: () {},
            onShiftTab: () {},
            onArrowAtEdge: (_) => false,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    controller.text = 'wip';
    await t.pump();
    await t.tap(find.byIcon(Icons.close));
    await t.pump();
    expect(controller.text, '');
    expect(find.byIcon(Icons.close), findsNothing);
    await t.tap(find.byIcon(Icons.open_in_full));
    expect(expanded, 1);
    controller.text = 'wip'; // both buttons, both tooltips
    await t.pump();
    await expectTooltipsInSemantics(t);
    focus.dispose();
    controller.dispose();
  });

  testWidgets('the first letter keeps the keyboard in the field (Windows accessibility focus)', (t) async {
    final semantics = t.ensureSemantics(); // disposed in the body: a tear-down runs after the check
    final controller = TextEditingController();
    final focus = FocusNode();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: CommitBox(
            controller: controller,
            focus: focus,
            onExpand: () {},
            label: 'Commit',
            enabled: true,
            onCommit: () {},
            onLeave: () {},
            onTab: () {},
            onShiftTab: () {},
            onArrowAtEdge: (_) => false,
          ),
        ),
      ),
    );
    await expectStableFocusWhileTyping(t, focus);
    semantics.dispose();
    focus.dispose();
    controller.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('hjkl and wasd type into the empty field; only the arrows step out of it', (t) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    final leaves = <NavDir>[];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: CommitBox(
            controller: controller,
            focus: focus,
            onExpand: () {},
            label: 'Commit',
            enabled: true,
            onCommit: () {},
            onLeave: () {},
            onTab: () {},
            onShiftTab: () {},
            onArrowAtEdge: (dir) {
              leaves.add(dir);
              return true;
            },
          ),
        ),
      ),
    );
    focus.requestFocus();
    await t.pump();

    // The letters, and the D-position key the layout reads as Right (matched by scan code).
    for (final (key, ch) in [
      (LogicalKeyboardKey.keyH, 'h'),
      (LogicalKeyboardKey.keyJ, 'j'),
      (LogicalKeyboardKey.keyK, 'k'),
      (LogicalKeyboardKey.keyL, 'l'),
      (LogicalKeyboardKey.keyW, 'w'),
      (LogicalKeyboardKey.keyA, 'a'),
      (LogicalKeyboardKey.keyS, 's'),
      (LogicalKeyboardKey.keyD, 'd'),
    ]) {
      final handled = await t.sendKeyEvent(key, character: ch);
      await t.pump();
      expect(handled, isFalse, reason: '$ch is typing, not a command');
      expect(focus.hasFocus, isTrue, reason: '$ch keeps the keyboard in the field');
    }
    expect(leaves, isEmpty, reason: 'no letter steps out of the field');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(leaves, [NavDir.left], reason: 'an arrow in the empty field still steps out');
  });

  testWidgets('the large window shows the message above git\'s comments and returns it without them', (t) async {
    String? result;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showCommitMessageDialog(
              context,
              message: 'first line',
              template: gitCommitTemplate(status()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, startsWith('first line\n\n# Please enter the commit message'));
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(result, 'first line');
  });
}
