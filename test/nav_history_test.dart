import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/ui/nav_history.dart';

void main() {
  test('back shows the places newest first and stops when empty', () {
    final history = NavHistory();
    final seen = <String>[];
    history.push(NavPlace('one', () => seen.add('one')));
    history.push(NavPlace('two', () => seen.add('two')));

    expect(history.canGoBack, isTrue);
    expect(history.label, 'two');
    expect(history.back(), isTrue);
    expect(seen, ['two']);
    expect(history.label, 'one');
    expect(history.back(), isTrue);
    expect(seen, ['two', 'one']);
    expect(history.back(), isFalse);
    expect(history.canGoBack, isFalse);
  });

  test('the oldest place falls off at the depth limit', () {
    final history = NavHistory();
    final seen = <int>[];
    for (var i = 0; i < NavHistory.maxDepth + 5; i++) {
      history.push(NavPlace('$i', () => seen.add(i)));
    }
    while (history.back()) {}
    expect(seen.length, NavHistory.maxDepth);
    expect(seen.first, NavHistory.maxDepth + 4, reason: 'back pops the newest first');
    expect(seen.last, 5, reason: 'the five oldest fell off');
  });

  test('clear empties the stack', () {
    final history = NavHistory()..push(NavPlace('somewhere', () {}));
    history.clear();
    expect(history.canGoBack, isFalse);
    expect(history.label, isNull);
  });
}
