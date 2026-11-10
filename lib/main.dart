import 'package:flutter/material.dart';

import 'ui/shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const NvimosApp());
}

class NvimosApp extends StatelessWidget {
  const NvimosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'nvimos',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Shell(),
    );
  }
}
