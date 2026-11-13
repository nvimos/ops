import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/parse.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/ui/tasks/rows.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  testWidgets('the progress of task rows is a column: same place and width in every row', (t) async {
    final s = Session();
    final ws = Workspace(s);
    String boxes(int done, int open) => [
      for (var i = 0; i < done; i++) '- [x] #${i + 1} d$i',
      for (var i = 0; i < open; i++) '- [ ] #${done + i + 1} o$i',
    ].join('\n');
    Task task(int n, String title, int done, int open) => parseTask('backlog/tasks/task-$n - t.md', [
      '---',
      'id: TASK-$n',
      'title: $title',
      'status: To Do',
      '---',
      '',
      if (done + open > 0) ...[
        '## Acceptance Criteria',
        '<!-- AC:BEGIN -->',
        ...boxes(done, open).split('\n'),
        '<!-- AC:END -->',
      ],
    ]);
    final tasks = [task(1, 'one', 1, 0), task(2, 'two with a longer title', 12, 8), task(3, 'none', 0, 0)];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Column(children: [for (final x in tasks) SizedBox(width: 800, height: 30, child: TaskRow(x, ws))]),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2)); // none in the row without checks
    final left = [
      for (final e in find.byType(LinearProgressIndicator).evaluate()) t.getTopLeft(find.byWidget(e.widget)).dx,
    ];
    expect(left[0], left[1]);
    final slots = find.byWidgetPredicate((w) => w is SizedBox && w.width == 74).evaluate().length;
    expect(slots, 3); // one slot per row
    ws.dispose();
    s.dispose();
  });
}
