import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/commit_template.dart';
import 'package:nvimos_poc/ui/changes_view.dart';
import 'package:nvimos_poc/ui/commit_message_dialog.dart';
import 'package:nvimos_poc/ui/theme.dart';

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
    focus.dispose();
    controller.dispose();
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
