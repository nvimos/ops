import 'dart:io';

import 'dart:ui' show AppExitResponse;

import 'package:material_ui/material_ui.dart';

import 'state/prefs.dart';
import 'state/session.dart';
import 'timing/ui_timing.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// Where the first command-line argument points: an existing directory (open it: start Neovim
/// there), else an address to connect to. Without an argument, [envAddress] (`NVIMOS_ADDR`).
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

/// Address of Neovim, or a directory to start it in: first command-line argument (an existing
/// directory there wins), else NVIMOS_ADDR, else 127.0.0.1:6666.
void main(List<String> args) {
  final target = launchTarget(args, envAddress: Platform.environment['NVIMOS_ADDR']);
  WidgetsFlutterBinding.ensureInitialized();
  UiTiming.instance.start();
  runApp(NvimosApp(address: target.address, directory: target.dir));
}

class NvimosApp extends StatefulWidget {
  const NvimosApp({super.key, this.address, this.directory});

  final String? address;

  /// A directory named on the command line: Neovim is started there and the app connects to it.
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
    final dir = widget.directory;
    if (dir != null) {
      _session.startNeovim(dir: dir);
    } else {
      _session.connect(address: widget.address);
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
