/// Editor detection and launching: which editor opens `{file}`, and how.
///
/// The order is the one in `PLAN.md`: the saved choice, `nvim-qt`, a resolvable
/// `git var GIT_EDITOR`, `VISUAL`, `EDITOR`, known editors on `PATH`, then
/// Notepad. Nothing here throws for a missing editor; only [Editors.open] fails,
/// with an [EditorException] the UI can show.
library;

import 'dart:io';

import 'system.dart';

/// A failure the user can act on, with no stack trace in the message.
class EditorException implements Exception {
  EditorException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What an editor can be asked to do besides open one file.
enum EditorCapability {
  /// `editor <folder>` opens the folder as a workspace, a tree or a listing.
  folder,
}

/// One editor the app can start, as a command template.
class EditorOption {
  const EditorOption({
    required this.id,
    required this.label,
    required this.command,
    this.detected = true,
    this.path,
    this.capabilities = const {},
  });

  final String id;
  final String label;

  /// Empty for an editor named by the environment: nothing is assumed about a
  /// command the user did not type in. The saved choice can open a folder.
  final Set<EditorCapability> capabilities;

  bool can(EditorCapability capability) => capabilities.contains(capability);

  /// The template handed to [Editors.expand]; `{file}`, may use `{line}`.
  final String command;

  /// False only for the "nothing found" placeholder.
  final bool detected;

  /// The executable or shim that was resolved, when there is one.
  final String? path;

  @override
  String toString() => '$id: $command';
}

/// Resolves a bare executable name to a full path, like `where` does.
typedef Which = Future<String?> Function(String exe);

/// True when an absolute path is a file that exists. Async: detection runs when
/// Settings opens, on the UI isolate, and must not block it on a stat.
typedef Exists = Future<bool> Function(String path);

/// Reads `git var GIT_EDITOR`, or null when git has no answer.
typedef GitEditorReader = Future<String?> Function();

/// The editors looked up on `PATH`, in the order `PLAN.md` lists them.
class KnownEditor {
  const KnownEditor(this.id, this.label, this.exe, {this.capabilities = const {}});

  final String id;
  final String label;
  final String exe;
  final Set<EditorCapability> capabilities;
}

const _folder = {EditorCapability.folder};

/// Vim-family editors open a folder as a netrw listing; the IDEs as a workspace.
const List<KnownEditor> knownEditors = [
  KnownEditor('code', 'VS Code', 'code', capabilities: _folder),
  KnownEditor('vim', 'Vim', 'vim', capabilities: _folder),
  KnownEditor('nvim', 'Neovim', 'nvim', capabilities: _folder),
  KnownEditor('gvim', 'gvim', 'gvim', capabilities: _folder),
  KnownEditor('notepad++', 'Notepad++', 'notepad++'),
  KnownEditor('zed', 'Zed', 'zed', capabilities: _folder),
  KnownEditor('hx', 'Helix', 'hx'),
  KnownEditor('subl', 'Sublime Text', 'subl', capabilities: _folder),
  KnownEditor('cursor', 'Cursor', 'cursor', capabilities: _folder),
  KnownEditor('idea64', 'IntelliJ IDEA', 'idea64', capabilities: _folder),
];

/// `nvim-qt` is found by its own lookup, not from [knownEditors].
const _nvimQtCapabilities = _folder;

/// Detection and launch. Every side effect is injectable, so the precedence
/// table is a plain unit test with no processes and no filesystem.
class Editors {
  /// [runner], [env] and [lister] are the machine; the function parameters
  /// replace one step each, for the precedence tests.
  Editors({
    this.savedCommand,
    Which? which,
    Exists? exists,
    GitEditorReader? gitEditor,
    Future<List<String>> Function()? nvimQtCandidates,
    Env? env,
    ProcessRunner runner = const SystemProcessRunner(),
    DirectoryLister lister = const SystemDirectoryLister(),
  }) : _runner = runner,
       _which = which ?? whichWith(runner),
       _exists = exists ?? lister.exists,
       _gitEditor = gitEditor ?? gitEditorWith(runner),
       _nvimQtCandidates =
           nvimQtCandidates ?? (() => nvimQtCandidatesIn(env ?? Env.system(), lister)),
       _env = env ?? Env.system();

  /// The command the user chose in Settings, or null: asked on every detection, so a change shows at once.
  final String? Function()? savedCommand;
  final ProcessRunner _runner;
  final Which _which;
  final Exists _exists;
  final GitEditorReader _gitEditor;
  final Future<List<String>> Function() _nvimQtCandidates;
  final Env _env;

  /// Every editor found, best first. A saved choice always leads; Notepad is
  /// the last resort; when literally nothing resolves the single entry is
  /// marked not detected instead of throwing.
  Future<List<EditorOption>> detect() async {
    final found = <EditorOption>[];

    final saved = savedCommand?.call();
    if (saved != null) {
      _append(
        found,
        EditorOption(
          id: 'saved',
          label: 'Your choice',
          command: saved,
          path: exeOf(saved),
          // The user's own command can be any program, and they chose it: it
          // is trusted to take a folder.
          capabilities: _folder,
        ),
      );
    }

    final nvimQt = await _nvimQtPath();
    if (nvimQt != null) _append(found, _fromPath('nvim-qt', 'nvim-qt', nvimQt, _nvimQtCapabilities));

    final git = await _fromCommand(
      'git',
      'git var GIT_EDITOR',
      await _gitEditedByGit(),
    );
    if (git != null) _append(found, git);

    final visual = await _fromCommand(
      'visual',
      'VISUAL',
      _env['VISUAL'],
    );
    if (visual != null) _append(found, visual);

    final editor = await _fromCommand(
      'editor',
      'EDITOR',
      _env['EDITOR'],
    );
    if (editor != null) _append(found, editor);

    for (final known in knownEditors) {
      final path = await _which(known.exe);
      if (path != null) _append(found, _fromPath(known.id, known.label, path, known.capabilities));
    }

    _append(
      found,
      const EditorOption(
        id: 'notepad',
        label: 'Notepad',
        command: 'notepad {file}',
      ),
    );

    if (found.isEmpty) {
      return const [
        EditorOption(
          id: 'none',
          label: 'No editor found',
          command: '',
          detected: false,
        ),
      ];
    }
    return found;
  }

  /// The editor to start now: the saved choice, else the first detected one.
  Future<EditorOption> chosenOption() async => (await detect()).first;

  /// The command template in use, for the Settings field.
  Future<String> chosen() async => (await chosenOption()).command;

  /// Open [file] at [line] in the chosen editor, detached from this app. A
  /// [folder] goes to the chosen editor if it can open one, else to the first
  /// detected editor that can; with none, it says so.
  Future<void> open({required String file, int? line, bool folder = false}) async {
    var option = await chosenOption();
    if (folder && option.detected && !option.can(EditorCapability.folder)) {
      final capable = (await detect()).where((it) => it.can(EditorCapability.folder));
      if (capable.isEmpty) throw EditorException('${option.label} cannot open a folder.');
      option = capable.first;
    }
    final command = option.command.trim();
    if (command.isEmpty) {
      throw EditorException('No editor is set. Pick one in Settings.');
    }
    final tokens = expand(command, file: file, line: line);
    final exe = tokens.first;
    final args = tokens.sublist(1);
    try {
      if (_isShim(exe)) {
        // A `.cmd` or `.bat` shim needs `cmd /c start` to open a window of its
        // own; `start` takes an empty title before the command.
        await _runner.startDetached('cmd', ['/c', 'start', '', exe, ...args]);
      } else {
        await _runner.startDetached(exe, args);
      }
    } on ProcessException catch (error) {
      throw EditorException(
        'Could not start ${option.label}: ${error.message}',
      );
    }
  }

  /// Open [folder] with the system's default action for folders: Explorer.
  Future<void> openFolderInSystem(String folder) async {
    try {
      await _runner.startDetached('explorer.exe', [folder.replaceAll('/', r'\')]);
    } on ProcessException catch (error) {
      throw EditorException('Could not open the folder: ${error.message}');
    }
  }

  /// Split a command template into an executable and its arguments, honouring
  /// double quotes so a path with spaces stays one token.
  static List<String> splitCommand(String command) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var hasToken = false;
    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        hasToken = true;
      } else if (!inQuotes && (char == ' ' || char == '\t')) {
        if (hasToken) {
          tokens.add(buffer.toString());
          buffer.clear();
          hasToken = false;
        }
      } else {
        buffer.write(char);
        hasToken = true;
      }
    }
    if (hasToken) tokens.add(buffer.toString());
    return tokens;
  }

  /// Fill `{file}` and `{line}` in a template and split it. A file with spaces
  /// is quoted first, so it survives the split. No `{file}` appends the path.
  static List<String> expand(
    String template, {
    required String file,
    int? line,
  }) {
    final quoted = file.contains(' ') ? '"$file"' : file;
    var text = template;
    if (text.contains('{file}')) {
      text = text.replaceAll('{file}', quoted);
    } else {
      text = '$text $quoted';
    }
    text = text.replaceAll('{line}', '${line ?? 1}');
    return splitCommand(text);
  }

  /// The executable at the head of a template, or null for an empty one.
  static String? exeOf(String command) {
    final tokens = splitCommand(command);
    return tokens.isEmpty ? null : tokens.first;
  }

  static bool _isShim(String exe) {
    final lower = exe.toLowerCase();
    return lower.endsWith('.cmd') || lower.endsWith('.bat');
  }

  static String _quote(String path) => '"$path"';

  EditorOption _fromPath(
    String id,
    String label,
    String path,
    Set<EditorCapability> capabilities,
  ) => EditorOption(
    id: id,
    label: label,
    command: '${_quote(path)} {file}',
    path: path,
    capabilities: capabilities,
  );

  /// An editor named by a command string (`git var`, `VISUAL`, `EDITOR`), kept
  /// only when its executable really resolves on this machine.
  Future<EditorOption?> _fromCommand(
    String id,
    String label,
    String? raw,
  ) async {
    final command = raw?.trim();
    if (command == null || command.isEmpty) return null;
    final exe = exeOf(command);
    if (exe == null) return null;
    if (!await _resolvable(exe)) return null;
    return EditorOption(
      id: id,
      label: label,
      command: command.contains('{file}') ? command : '$command {file}',
      path: exe,
    );
  }

  Future<String?> _gitEditedByGit() async {
    try {
      return await _gitEditor();
    } on Exception {
      return null;
    }
  }

  /// `vi` and `vim` are reported by git but usually absent on Windows, so they
  /// only count when `vi` itself is on `PATH`.
  Future<bool> _resolvable(String exe) async {
    final name = _baseName(exe);
    if (name == 'vi' || name == 'vim') return await _which('vi') != null;
    if (exe.contains('/') || exe.contains(r'\')) return await _exists(exe);
    return await _which(exe) != null;
  }

  static String _baseName(String exe) {
    final tail = exe.replaceAll(r'\', '/').split('/').last.toLowerCase();
    return tail.endsWith('.exe') ? tail.substring(0, tail.length - 4) : tail;
  }

  Future<String?> _nvimQtPath() async {
    final onPath = await _which('nvim-qt');
    if (onPath != null) return onPath;
    for (final candidate in await _nvimQtCandidates()) {
      if (await _exists(candidate)) return candidate;
    }
    return null;
  }

  /// Add [option] unless the same command is already listed.
  static void _append(List<EditorOption> found, EditorOption option) {
    if (option.command.trim().isEmpty) return;
    final command = option.command.replaceAll('/', r'\').toLowerCase();
    if (found.any(
      (other) => other.command.replaceAll('/', r'\').toLowerCase() == command,
    )) {
      return;
    }
    found.add(option);
  }

  /// `where` can find several matches (the exe, then a `.bat` wrapper earlier on
  /// PATH). A `.bat`/`.cmd` is started through `cmd /c start`, which shows a
  /// console window, so a real `.exe` is preferred whenever one is listed.
  static Which whichWith(ProcessRunner runner) => (exe) async {
    try {
      final result = await runner.run('where', [exe]);
      if (!result.ok) return null;
      return pickFromWhere(result.stdout);
    } on ProcessException {
      return null;
    }
  };

  /// The best of `where`'s lines: `.exe` first, then a shim Windows can start
  /// through cmd, then anything; null for no line.
  static String? pickFromWhere(String output) {
    final found = output
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (found.isEmpty) return null;
    for (final value in found) {
      if (value.toLowerCase().endsWith('.exe')) return value;
    }
    for (final value in found) {
      if (_isShim(value)) return value;
    }
    return found.first;
  }

  static GitEditorReader gitEditorWith(ProcessRunner runner) => () async {
    try {
      final result = await runner.run('git', ['var', 'GIT_EDITOR']);
      if (!result.ok) return null;
      final out = result.stdout.trim();
      return out.isEmpty ? null : out;
    } on ProcessException {
      return null;
    }
  };

  /// `%ProgramFiles%\neovim-qt*\bin\nvim-qt.exe`, without pulling in a glob
  /// package: walk the one level that can match.
  static Future<List<String>> nvimQtCandidatesIn(Env env, DirectoryLister lister) async {
    final roots = [env['ProgramFiles'], env['ProgramFiles(x86)']].whereType<String>();
    final found = <String>[];
    for (final root in roots) {
      try {
        for (final entry in await lister.list(root)) {
          final name = entry.path.replaceAll(r'\', '/').split('/').lastWhere(
            (part) => part.isNotEmpty,
            orElse: () => '',
          );
          if (!name.toLowerCase().startsWith('neovim-qt')) continue;
          found.add('${entry.path.replaceAll(r'\', '/')}/bin/nvim-qt.exe');
        }
      } on FileSystemException {
        // An unreadable Program Files is simply no candidates.
      }
    }
    return found;
  }
}
