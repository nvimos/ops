import 'package:flutter/material.dart';

import '../state/session.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shown while not connected: address, Connect, and how to start Neovim.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _addr;

  /// Ways to start a Neovim the app can connect to.
  static const _howTo =
      'nvim --listen 127.0.0.1:6666\n'
      ':NvimosServe        (in a running Neovim)\n'
      'make nvim           (in nvimos-poc-frontend)';

  @override
  void initState() {
    super.initState();
    _addr = TextEditingController(text: SessionScope.read(context).address);
  }

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  void _connect() => SessionScope.read(context).connect(address: _addr.text.trim());

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Center(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Connect to Neovim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Start Neovim with the nvimos plugin listening, then connect. The app retries every 2 seconds.', style: T.small),
            const SizedBox(height: 16),
            AddressRow(controller: _addr, busy: s.conn == Conn.connecting, onConnect: _connect),
            if (s.error != null) ConnectError(s.error!),
            const SizedBox(height: 20),
            const CodeBox(_howTo),
          ],
        ),
      ),
    );
  }
}

/// The address field and the Connect button; Enter in the field connects too.
class AddressRow extends StatelessWidget {
  const AddressRow({super.key, required this.controller, required this.busy, required this.onConnect});

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: TextField(controller: controller, style: T.body, onSubmitted: (_) => onConnect())),
      const SizedBox(width: 8),
      SmallButton(busy ? 'Connecting…' : 'Connect', primary: true, onPressed: busy ? null : onConnect),
    ],
  );
}

class ConnectError extends StatelessWidget {
  const ConnectError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: SelectableText(text, style: const TextStyle(fontSize: 12, color: C.yellow)),
  );
}

/// Selectable monospace text on a bordered box, for commands to copy.
class CodeBox extends StatelessWidget {
  const CodeBox(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: C.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: C.border),
    ),
    child: SelectableText(text, style: T.code),
  );
}
