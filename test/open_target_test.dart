import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/backend/models.dart';
import 'package:nvimos_poc/state/dirs.dart';

void main() {
  Branches branches(List<String> names, {String current = 'main'}) => Branches({
    'current': current,
    'branches': [
      for (final n in names) {'name': n, 'sha': 'abc', 'date': 0},
    ],
  });
  Status status(int files) => Status({
    'branch': 'main',
    'files': [
      for (var i = 0; i < files; i++) {'path': 'f$i.txt', 'index': ' ', 'worktree': 'M'},
    ],
  });

  test('a branch besides main opens the Pull request mode, dirty or not', () {
    expect(openTarget(branches(['main', 'feat']), status(0)), OpenTarget.pullRequest);
    expect(openTarget(branches(['master', 'feat'], current: 'feat'), status(3)), OpenTarget.pullRequest);
  });

  test('only the default branch and a dirty checkout: Changes', () {
    expect(openTarget(branches(['main']), status(2)), OpenTarget.changes);
    expect(openTarget(branches(['master'], current: 'master'), status(1)), OpenTarget.changes);
  });

  test('only the default branch and a clean checkout: Tasks', () {
    expect(openTarget(branches(['master'], current: 'master'), status(0)), OpenTarget.tasks);
    expect(openTarget(branches(['trunk'], current: 'trunk'), status(0)), OpenTarget.tasks);
    expect(openTarget(branches([]), status(0)), OpenTarget.tasks);
  });
}
