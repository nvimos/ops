import 'dart:io';

final _made = <Directory>[];

/// Remember a temp dir a test made, so [removeTempDirs] deletes it when the test file is done.
T keepForCleanup<T extends FileSystemEntity>(T d) {
  if (d is Directory) _made.add(d);
  return d;
}

/// Delete the dirs made by this test file. A dir that is still in use (Windows locks a process's
/// cwd) is left; the OS temp cleanup gets it.
Future<void> removeTempDirs() async {
  for (final d in _made) {
    try {
      if (d.existsSync()) d.deleteSync(recursive: true);
    } on FileSystemException {
      // in use: leave it
    }
  }
  _made.clear();
}
