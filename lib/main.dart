import 'dart:io';

import 'package:flutter/material.dart';

import 'state/session.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// Address of Neovim: first command-line argument, or NVIMOS_ADDR, or 127.0.0.1:6666.
void main(List<String> args) {
  final addr = args.isNotEmpty ? args.first : Platform.environment['NVIMOS_ADDR'];
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

  @override
  void initState() {
    super.initState();
    _session.connect(address: widget.address);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: _session,
      child: MaterialApp(
        title: 'nvimos',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      ),
    );
  }
}
