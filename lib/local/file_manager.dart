/// Open a folder the way the desktop does: Explorer on Windows, Finder on macOS,
/// whatever `xdg-open` is set to on Linux.
library;

import 'dart:io';

import 'system.dart';

/// A folder that could not be shown, in one line.
class FileManagerException implements Exception {
  FileManagerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FileManager {
  FileManager({this.runner = const SystemProcessRunner(), Env? env}) : env = env ?? Env.system();

  final ProcessRunner runner;
  final Env env;

  /// The program and arguments that show [folder] on this platform.
  (String, List<String>) command(String folder) {
    if (env.isWindows) return ('explorer.exe', [folder.replaceAll('/', r'\')]);
    if (env.isMacOS) return ('open', [folder]);
    return ('xdg-open', [folder]);
  }

  /// The program and arguments that open [file] as a double click would: the
  /// default app for a document, the program itself for an executable. Explorer
  /// does both on Windows; macOS `open` too; Linux `xdg-open` opens documents
  /// but does not run programs, so a [program] there is started directly.
  (String, List<String>) launchCommand(String file, {bool program = false}) {
    if (env.isWindows) return ('explorer.exe', [file.replaceAll('/', r'\')]);
    if (env.isMacOS) return ('open', [file]);
    return program ? (file, const []) : ('xdg-open', [file]);
  }

  /// Open [file] the way the desktop does. Detached, like [open].
  Future<void> launch(String file, {bool program = false}) async {
    if (!await File(file).exists()) throw FileManagerException('$file is not on disk');
    final (exe, args) = launchCommand(file, program: program);
    try {
      await runner.startDetached(exe, args);
    } on ProcessException catch (error) {
      throw FileManagerException('Could not open the file with $exe: ${error.message}');
    }
  }

  /// The command that hands a web address to the system: its default browser (or mail app) opens it.
  (String, List<String>) urlCommand(String url) {
    if (env.isWindows) return ('explorer.exe', [url]);
    if (env.isMacOS) return ('open', [url]);
    return ('xdg-open', [url]);
  }

  /// Open [url] the way the system opens a link. Detached, like [launch].
  Future<void> openUrl(String url) async {
    final (exe, args) = urlCommand(url);
    try {
      await runner.startDetached(exe, args);
    } on ProcessException catch (error) {
      throw FileManagerException('Could not open $url with $exe: ${error.message}');
    }
  }

  /// Show [folder]. Detached: Explorer answers 1 even when it worked, and the
  /// window is the user's, not ours.
  Future<void> open(String folder) async {
    final (exe, args) = command(folder);
    try {
      await runner.startDetached(exe, args);
    } on ProcessException catch (error) {
      throw FileManagerException('Could not open the folder with $exe: ${error.message}');
    }
  }
}
