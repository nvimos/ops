/// Terminals on this machine, and starting the one Browse's context menu uses.
///
/// Detection is `where`, like the editors: a terminal is offered only when its
/// executable resolves. Windows Terminal leads the list, so it is the default
/// when several are installed; a choice saved in Settings wins over it.
library;

import 'dart:io';

import 'editors.dart';
import 'system.dart';

/// A terminal that could not be started, in one line.
class TerminalException implements Exception {
  TerminalException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How a terminal is started: directly, or through `cmd /c start` so a console
/// program gets a window of its own.
enum TerminalWindow {
  /// A GUI terminal, or one that makes its own window (`wt`, WezTerm).
  direct,

  /// A console shell (`pwsh`, `powershell`, `cmd`) that needs a console.
  console,
}

/// One terminal the app knows how to start. [args] may hold `{folder}`.
class KnownTerminal {
  const KnownTerminal(
    this.id,
    this.label,
    this.exe, {
    this.args = const [],
    this.window = TerminalWindow.direct,
  });

  final String id;
  final String label;
  final String exe;
  final List<String> args;
  final TerminalWindow window;
}

/// The terminals looked up on `PATH`. Windows Terminal is first on purpose:
/// with no saved choice, the first one found is the one the menu starts.
const List<KnownTerminal> knownTerminals = [
  KnownTerminal('wt', 'Windows Terminal', 'wt.exe', args: ['-d', '{folder}']),
  KnownTerminal('wezterm', 'WezTerm', 'wezterm.exe', args: ['start', '--cwd', '{folder}']),
  KnownTerminal(
    'alacritty',
    'Alacritty',
    'alacritty.exe',
    args: ['--working-directory', '{folder}'],
  ),
  KnownTerminal('pwsh', 'PowerShell 7', 'pwsh.exe', window: TerminalWindow.console),
  KnownTerminal(
    'powershell',
    'Windows PowerShell',
    'powershell.exe',
    window: TerminalWindow.console,
  ),
  KnownTerminal('cmd', 'Command Prompt', 'cmd.exe', window: TerminalWindow.console),
];

/// One terminal found on this machine.
class TerminalOption {
  const TerminalOption({
    required this.id,
    required this.label,
    required this.exe,
    this.args = const [],
    this.window = TerminalWindow.direct,
  });

  final String id;
  final String label;
  final String exe;
  final List<String> args;
  final TerminalWindow window;

  /// [args] with the folder filled in.
  List<String> argsIn(String folder) => [
    for (final arg in args) arg.replaceAll('{folder}', folder),
  ];
}

/// Finds the terminals on `PATH` and starts one, detached from this app.
class TerminalLauncher {
  TerminalLauncher({ProcessRunner runner = const SystemProcessRunner(), Which? which})
    : _runner = runner,
      _which = which ?? Editors.whichWith(runner);

  final ProcessRunner _runner;
  final Which _which;

  /// Every known terminal that resolves, in [knownTerminals] order.
  Future<List<TerminalOption>> detect() async {
    final found = <TerminalOption>[];
    for (final known in knownTerminals) {
      final path = await _which(known.exe);
      if (path == null) continue;
      found.add(
        TerminalOption(
          id: known.id,
          label: known.label,
          exe: path,
          args: known.args,
          window: known.window,
        ),
      );
    }
    return found;
  }

  /// The saved choice when it is still found, else the first detected one
  /// (Windows Terminal when it is installed), else null.
  static TerminalOption? pick(List<TerminalOption> found, String? saved) {
    if (found.isEmpty) return null;
    for (final option in found) {
      if (option.id == saved) return option;
    }
    return found.first;
  }

  /// Start [terminal] in [folder]: the folder is its working directory, and a
  /// direct terminal also gets it as an argument where one is needed.
  Future<void> start(TerminalOption terminal, String folder) async {
    final args = terminal.argsIn(folder);
    try {
      if (terminal.window == TerminalWindow.console) {
        // `start` takes an empty title, then the program to give a window.
        await _runner.startDetached('cmd', ['/c', 'start', '', terminal.exe, ...args], cwd: folder);
      } else {
        await _runner.startDetached(terminal.exe, args, cwd: folder);
      }
    } on ProcessException catch (error) {
      throw TerminalException('Could not start ${terminal.label}: ${error.message}');
    }
  }
}
