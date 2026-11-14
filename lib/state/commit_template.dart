import '../backend/models.dart';

/// The comment block git puts under the message when it opens an editor for `git commit`: what to
/// do, the branch, and the files staged, changed and untracked. Every line starts with `#`.
String gitCommitTemplate(Status? status) {
  final files = status?.files ?? const <StatusFile>[];
  final staged = [for (final f in files) if (f.staged) f];
  final unstaged = [for (final f in files) if (f.unstaged && !f.untracked) f];
  final untracked = [for (final f in files) if (f.untracked) f];
  final out = <String>[
    '# Please enter the commit message for your changes. Lines starting',
    "# with '#' will be ignored, and an empty message aborts the commit.",
    '#',
    '# On branch ${status?.branch ?? '(detached)'}',
    if (staged.isNotEmpty) ...[
      '# Changes to be committed:',
      for (final f in staged) _line(f, f.index),
      '#',
    ],
    if (unstaged.isNotEmpty) ...[
      '# Changes not staged for commit:',
      for (final f in unstaged) _line(f, f.worktree),
      '#',
    ],
    if (untracked.isNotEmpty) ...[
      '# Untracked files:',
      for (final f in untracked) '#\t${f.path}',
      '#',
    ],
  ];
  return out.join('\n');
}

String _line(StatusFile f, String code) {
  final what = switch (code.trim()) {
    'A' => 'new file:',
    'D' => 'deleted:',
    'R' => 'renamed:',
    'C' => 'copied:',
    'T' => 'typechange:',
    'U' => 'unmerged:',
    _ => 'modified:',
  };
  final name = f.orig != null && code.trim() == 'R' ? '${f.orig} -> ${f.path}' : f.path;
  return '#\t${what.padRight(11)} $name';
}

/// [text] without its comment lines (those starting with `#`) and with the blank lines at both
/// ends trimmed, as git saves a message written in an editor.
String stripCommitComments(String text) {
  final lines = [for (final l in text.split('\n')) if (!l.startsWith('#')) l.trimRight()];
  return lines.join('\n').trim();
}
