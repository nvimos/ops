import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/browser.dart';
import 'package:nvimos_poc/tasks/parse.dart';
import 'package:nvimos_poc/tasks/workspace.dart';

void main() {
  test('the sidebar labels sort by name, or by task count (most first, then name)', () {
    final s = Session();
    final ws = Workspace(s); // not connected: load() does nothing
    var n = 0;
    final task = (String labels) =>
        parseTask('backlog/tasks/task-${++n} - t.md', ['---', 'id: TASK-$n', 'title: t', 'labels: [$labels]', '---']);
    ws.tasks = [task('b, z'), task('z'), task('z, a'), task('b')];
    final browser = TaskBrowser(ws, lastSeen: () => DateTime(2000));

    List<String> names() => browser.navLabels().map((l) => '${l.label}:${l.count}').toList();
    expect(names(), ['a:1', 'b:2', 'z:3']);
    browser.toggleLabelSort();
    expect(names(), ['z:3', 'b:2', 'a:1']);
    browser.toggleLabelSort();
    expect(names(), ['a:1', 'b:2', 'z:3']);

    // Collapsed at first; the toggle opens and closes the list.
    expect(browser.labelsOpen, isFalse);
    browser.toggleLabelsOpen();
    expect(browser.labelsOpen, isTrue);

    browser.dispose();
    ws.dispose();
    s.dispose();
  });
}
