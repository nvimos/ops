import 'dart:io';

import 'package:path/path.dart' as p;

/// The host's path rules: separators, roots and parent lookup, so the app can run
/// on Windows and on Linux without hardcoded separators or drive letters.
final p.Context hostPaths = Platform.isWindows ? p.windows : p.posix;

/// A path in the form the app stores and shows: host-canonical, with forward
/// slashes so rows, the console and the spec read the same on both platforms.
String canonicalPath(String path) {
  final normalized = hostPaths.normalize(path);
  return Platform.isWindows ? normalized.replaceAll(r'\', '/') : normalized;
}

/// Absolute path of [relative] inside [root], in the canonical form above.
String pathIn(String root, String relative) =>
    canonicalPath(hostPaths.join(canonicalPath(root), relative));
