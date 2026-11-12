import 'dart:io';

/// The folder names of a relay checkout (the backend plugin): its repo name, and the POC folder.
const backendFolders = ['relay', 'nvimos-poc-backend'];

/// The backend plugin checkout: NVIMOS_BACKEND, or a `relay` (or `nvimos-poc-backend`) folder with
/// `plugin/nvimos.lua` in it, next to the app's folder or one of its parents (found from the
/// working directory, then from the exe).
String? findBackendDir({Map<String, String>? env, List<String>? starts}) {
  final set = (env ?? Platform.environment)['NVIMOS_BACKEND'];
  if (set != null && set.isNotEmpty) return set.replaceAll('\\', '/');
  for (final start in starts ?? [Directory.current.path, File(Platform.resolvedExecutable).parent.path]) {
    var dir = Directory(start).absolute;
    while (true) {
      for (final name in backendFolders) {
        final candidate = Directory('${dir.path}/$name');
        if (File('${candidate.path}/plugin/nvimos.lua').existsSync()) return candidate.path.replaceAll('\\', '/');
      }
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

/// How [launchNeovim] starts Neovim.
enum NvimKind {
  /// `nvim` in its own console window.
  console('nvim', 'Neovim'),

  /// `nvim-qt`, the GUI; its embedded nvim gets the arguments after `--`.
  qt('nvim-qt', 'nvim-qt'),

  /// `nvim --headless`, detached from the app: no window, no terminal, and it keeps running after
  /// the app quits. [stopHeadless] ends them.
  headless('nvim', 'headless Neovim');

  const NvimKind(this.exe, this.label);

  final String exe, label;
}

/// nvim-qt's own options, as the user starts it: dark title bar, and the config's stylesheet
/// (`%LOCALAPPDATA%\nvim\nvim-qt.qss`) when it exists.
List<String> qtArgs({Map<String, String>? env, bool Function(String path)? exists}) {
  final local = (env ?? Platform.environment)['LOCALAPPDATA'];
  final qss = local == null ? null : '$local\\nvim\\nvim-qt.qss';
  final has = exists ?? (String p) => File(p).existsSync();
  return ['-platform', 'windows:darkmode=1', if (qss != null && has(qss)) ...['-stylesheet', qss]];
}

/// The command line for [kind]: (executable, arguments). [qt] replaces [qtArgs] (tests).
(String, List<String>) nvimCommand(NvimKind kind, String address, String backendDir, {List<String>? qt}) {
  final args = nvimArgs(address, backendDir);
  return switch (kind) {
    // `start` gives Neovim a console; the app has none. The first quoted argument is the title.
    NvimKind.console => ('cmd', ['/c', 'start', 'nvimos nvim', 'nvim', ...args]),
    NvimKind.qt => ('nvim-qt', [...qt ?? qtArgs(), '--', ...args]),
    NvimKind.headless => ('nvim', ['--headless', ...args]),
  };
}

/// Start Neovim as [kind], listening on [address] with the backend plugin; returns why it could not,
/// or null.
Future<String?> launchNeovim(String address, {NvimKind kind = NvimKind.console}) async {
  try {
    final backend = findBackendDir();
    if (backend == null) return 'the relay plugin not found; set NVIMOS_BACKEND to its checkout';
    final where = await Process.run('where', [kind.exe]);
    if (where.exitCode != 0) return '${kind.exe} is not on PATH';
    final (exe, args) = nvimCommand(kind, address, backend);
    await Process.start(exe, args, mode: ProcessStartMode.detached);
    return null;
  } on ProcessException catch (e) {
    return 'could not start ${kind.exe}: ${e.message}';
  } catch (e) {
    return 'could not start ${kind.exe}: $e';
  }
}

/// The command line that opens [file] at [line] in a new nvim-qt, on its own (no server, no plugin).
List<String> qtOpenArgs(String file, int line, {List<String>? qt}) => [...qt ?? qtArgs(), '--', '+$line', file];

/// Open [file] (absolute) at [line] in a new nvim-qt window; returns why it could not, or null.
Future<String?> openInQt(String file, int line) async {
  final where = await Process.run('where', ['nvim-qt']);
  if (where.exitCode != 0) return 'nvim-qt is not on PATH';
  try {
    await Process.start('nvim-qt', qtOpenArgs(file, line), mode: ProcessStartMode.detached);
    return null;
  } on ProcessException catch (e) {
    return 'could not start nvim-qt: ${e.message}';
  }
}

/// PowerShell that stops every `nvim.exe` of this user started with `--headless` and prints how many.
const stopHeadlessScript = r"""
$me = [Environment]::UserName
$p = @(Get-CimInstance Win32_Process -Filter "Name='nvim.exe'" |
  Where-Object { $_.CommandLine -match '--headless' -and (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User -eq $me })
$p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$p.Count
""";

/// Stop every headless Neovim of this user (found in the process list); returns (how many, error).
Future<(int, String?)> stopHeadless() async {
  try {
    final r = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', stopHeadlessScript]);
    if (r.exitCode != 0) return (0, 'could not stop headless Neovim: ${'${r.stderr}'.trim()}');
    return (int.tryParse('${r.stdout}'.trim().split('\n').last.trim()) ?? 0, null);
  } on ProcessException catch (e) {
    return (0, 'could not stop headless Neovim: ${e.message}');
  }
}
