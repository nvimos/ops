import 'dart:io';

import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'state/session.dart';
import 'timing/ui_timing.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// Address of Neovim: first command-line argument, or NVIMOS_ADDR, or 127.0.0.1:6666.
void main(List<String> args) {
  final addr = args.isNotEmpty ? args.first : Platform.environment['NVIMOS_ADDR'];
  WidgetsFlutterBinding.ensureInitialized();
  UiTiming.instance.start();
  runApp(NvimosApp(address: addr));
}

class NvimosApp extends StatefulWidget {
  const NvimosApp({super.key, this.address});

  final String? address;

  @override
  State<NvimosApp> createState() => _NvimosAppState();
}

class _NvimosAppState extends State<NvimosApp> {
  final _session = Session();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExit);
    _session.connect(address: widget.address);
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
