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

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final busy = s.conn == Conn.connecting;
    return Center(
      child: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Connect to Neovim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Start Neovim with the nvimos plugin listening, then connect. The app retries every 2 seconds.',
              style: T.small),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _addr,
                style: T.body,
                onSubmitted: (v) => s.connect(address: v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            SmallButton(busy ? 'Connecting…' : 'Connect',
                primary: true, onPressed: busy ? null : () => s.connect(address: _addr.text.trim())),
          ]),
          if (s.error != null) ...[
            const SizedBox(height: 10),
            Text(s.error!, style: const TextStyle(fontSize: 12, color: C.yellow)),
          ],
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: C.border)),
            child: const SelectableText(
              'nvim --listen 127.0.0.1:6666\n'
              ':NvimosServe        (in a running Neovim)\n'
              'make nvim           (in nvimos-poc-frontend)',
              style: T.code,
            ),
          ),
        ]),
      ),
    );
  }
}
