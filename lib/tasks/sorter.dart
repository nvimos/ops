import 'package:flutter/widgets.dart';

/// One way to order a list: its name (the tooltip), a one-word [word] for the label beside the
/// button, its icon, and the comparison.
/// [warning] returns a note when the data this mode sorts by looks unreliable.
class SortMode<T> {
  const SortMode(this.label, this.word, this.icon, this.compare, {this.warning});

  final String label;
  final String word;
  final IconData icon;
  final int Function(T a, T b) compare;
  final String? Function()? warning;
}

/// The sorting of one list: the current mode, cycled by a button, and the direction, turned
/// round by another. Shown by `SortButtons`; any list can have one.
class Sorter<T> extends ChangeNotifier {
  Sorter(this.modes, {int start = 0, this.descending = false}) : index = start;

  final List<SortMode<T>> modes;
  int index;
  bool descending;

  SortMode<T> get mode => modes[index];

  /// The tooltip of the mode button: the mode, and the mode's warning if it has one.
  String get tooltip {
    final w = mode.warning?.call();
    return w == null ? mode.label : '${mode.label}\n$w';
  }

  void cycle() {
    index = (index + 1) % modes.length;
    notifyListeners();
  }

  void reverse() {
    descending = !descending;
    notifyListeners();
  }

  /// [items] in the current order; ties keep their incoming order.
  List<T> sorted(Iterable<T> items) {
    final keyed = items.toList().asMap().entries.toList()
      ..sort((a, b) {
        final c = descending ? mode.compare(b.value, a.value) : mode.compare(a.value, b.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in keyed) e.value];
  }
}
