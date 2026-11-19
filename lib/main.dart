import 'dart:io';

import 'dart:ui' show AppExitResponse;

import 'package:material_ui/material_ui.dart';

import 'state/prefs.dart';
import 'state/session.dart';
import 'timing/ui_timing.dart';
import 'ui/input_modality.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// Where the first command-line argument points: an existing directory (open it with the local
/// backend, no Neovim), else an address to connect to (the Neovim backend). Without an argument, [envAddress] (`NVIMOS_ADDR`).
/// [isDir] replaces the file-system check (tests).
({String? dir, String? address}) launchTarget(
  List<String> args, {
  String? envAddress,
  bool Function(String path)? isDir,
}) {
  final arg = args.isEmpty ? null : args.first;
  if (arg == null) return (dir: null, address: envAddress);
  if ((isDir ?? (p) => Directory(p).existsSync())(arg)) {
    return (dir: Directory(arg).absolute.path, address: null);
  }
  return (dir: null, address: arg);
}

/// The folder to open locally when the command line names nothing: the last folder opened with the
/// local backend that still exists, else [cwd]. Local mode is the default; Neovim only when an
/// address is given (argument or `NVIMOS_ADDR`) or picked on the connect screen.
String startupFolder(List<Recent> recents, String cwd, {bool Function(String path)? isDir}) {
  final exists = isDir ?? (p) => Directory(p).existsSync();
  for (final r in recents) {
    if (r.kind == BackendKind.local && exists(r.target)) return r.target;
  }
  return cwd;
}

/// A directory to open locally or the address of Neovim: the first command-line argument (an
/// existing directory there wins), else NVIMOS_ADDR; with neither, the [startupFolder] locally.
void main(List<String> args) {
  final target = launchTarget(args, envAddress: Platform.environment['NVIMOS_ADDR']);
  WidgetsFlutterBinding.ensureInitialized();
  UiTiming.instance.start();
  InputModality.instance.watch();
  runApp(NvimosApp(address: target.address, directory: target.dir));
}

class NvimosApp extends StatefulWidget {
  const NvimosApp({super.key, this.address, this.directory});

  final String? address;

  /// A directory named on the command line: it is opened with the local backend.
  final String? directory;

  @override
  State<NvimosApp> createState() => _NvimosAppState();
}

class _NvimosAppState extends State<NvimosApp> {
  final _session = Session(prefs: Prefs.load());
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExit);
    final address = widget.address;
    if (address != null && widget.directory == null) {
      _session.connect(address: address);
    } else {
      final dir = widget.directory ?? startupFolder(_session.recents, Directory.current.path);
      _session.openFolder(dir, openProject: true);
    }
  }

  /// Closing the window: write this session's UI timings, then quit.
  Future<AppExitResponse> _onExit() async {
    await UiTiming.instance.save(closing: true);
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: _session,
      child: MaterialApp(title: 'nvimos', debugShowCheckedModeBanner: false, theme: buildTheme(), home: const Shell()),
    );
  }
}
