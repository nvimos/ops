import 'dart:io';

/// The backend plugin checkout: NVIMOS_BACKEND, or `nvimos-poc-backend` next to the app's
/// folder or one of its parents (found from the working directory, then from the exe).
String? findBackendDir({Map<String, String>? env, List<String>? starts}) {
  final set = (env ?? Platform.environment)['NVIMOS_BACKEND'];
  if (set != null && set.isNotEmpty) return set.replaceAll('\\', '/');
  for (final start in starts ?? [Directory.current.path, File(Platform.resolvedExecutable).parent.path]) {
    var dir = Directory(start).absolute;
    while (true) {
      final candidate = Directory('${dir.path}/nvimos-poc-backend');
      if (candidate.existsSync()) return candidate.path.replaceAll('\\', '/');
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
  }
  return null;
}

/// The arguments for a Neovim listening on [address] with the backend plugin loaded
/// after the user's config (which may reset 'runtimepath'), like `make nvim`.
List<String> nvimArgs(String address, String backendDir) => [
  '--listen',
  address,
  '-c',
  'set rtp^=$backendDir',
  '-c',
  'runtime plugin/nvimos.lua',
];

/// Start Neovim in its own console window; returns why it could not, or null.
Future<String?> launchNeovim(String address) async {
  final backend = findBackendDir();
  if (backend == null) return 'nvimos-poc-backend not found; set NVIMOS_BACKEND';
  final where = await Process.run('where', ['nvim']);
  if (where.exitCode != 0) return 'nvim is not on PATH';
  try {
    // `start` gives Neovim a console; the app has none. The first quoted argument is the title.
    await Process.start('cmd', [
      '/c',
      'start',
      'nvimos nvim',
      'nvim',
      ...nvimArgs(address, backend),
    ], mode: ProcessStartMode.detached);
    return null;
  } on ProcessException catch (e) {
    return 'could not start nvim: ${e.message}';
  }
}
