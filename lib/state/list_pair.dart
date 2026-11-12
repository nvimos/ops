/// Two lists stacked in a sidebar, top (0) and bottom (1): which one gets the most room and which
/// are folded to their header. Pull request: files over commits; Changes: staged over unstaged.
/// Lasts for the session; the owner calls notifyListeners after a change.
class ListPair {
  ListPair({this.dominant = 0});

  /// The list that takes the free height.
  int dominant;

  /// Folded lists show only their header.
  final collapsed = [false, false];

  /// The "most room" button: on the dominant list it hands the room to the other one.
  /// The list that gets the room unfolds.
  void toggleDominant(int i) {
    dominant = dominant == i ? 1 - i : i;
    collapsed[dominant] = false;
  }

  /// A click on the header: fold or unfold the list; a folded dominant list hands the room on.
  void toggleCollapsed(int i) {
    collapsed[i] = !collapsed[i];
    if (collapsed[i] && dominant == i) dominant = 1 - i;
  }
}

/// The folders of [paths] to fold for "collapse all": all but [keep]'s (the selected file's).
/// Top-level files have no folder row, so '' never folds.
Set<String> foldAll(Iterable<String> paths, {String? keep}) => {for (final p in paths) dirOf(p)}
  ..remove('')
  ..remove(dirOf(keep ?? ''));

/// Orders paths as the file tree lists them: by folder (top-level files first), then by path.
int compareTreeOrder(String a, String b) {
  final d = dirOf(a).compareTo(dirOf(b));
  return d != 0 ? d : a.compareTo(b);
}

/// The folder part of a path; '' for a top-level file.
String dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}
