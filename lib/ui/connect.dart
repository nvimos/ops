import 'package:material_ui/material_ui.dart';

import '../state/nvim_launcher.dart';
import '../state/session.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shown while not connected: address, Retry, Start Neovim, and how to start it by hand.
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
      'make nvim           (in the ops checkout)';

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

  Future<void> _startNeovim(NvimKind kind) async {
    final s = SessionScope.read(context);
    try {
      final addr = _addr.text.trim();
      if (addr != s.address) await s.connect(address: addr);
      await s.startNeovim(kind: kind);
    } catch (e) {
      s.showError('could not start ${kind.label}: $e');
    }
  }

  void _cancel() => SessionScope.read(context).cancelConnect();

  void _stopHeadless() => SessionScope.read(context).stopHeadlessNeovims();

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
            const Text('Start Neovim with the nvimos plugin listening, then retry.', style: T.small),
            const SizedBox(height: 16),
            AddressRow(
              controller: _addr,
              busy: s.conn == Conn.connecting || s.starting != null,
              onConnect: _connect,
              onCancel: _cancel,
            ),
            const SizedBox(height: 8),
            StartButtons(
              starting: s.starting,
              enabled: s.conn == Conn.disconnected,
              onStart: _startNeovim,
              onStopHeadless: _stopHeadless,
            ),
            if (s.error != null) ConnectError(s.error!),
            if (s.notice != null) ConnectNotice(s.notice!),
            const SizedBox(height: 20),
            const CodeBox(_howTo),
          ],
        ),
      ),
    );
  }
}

/// The address field and the Retry button; Enter in the field connects too.
/// While [busy] the button is Cancel.
class AddressRow extends StatelessWidget {
  const AddressRow({
    super.key,
    required this.controller,
    required this.busy,
    required this.onConnect,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onConnect, onCancel;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: TextField(controller: controller, style: T.body, onSubmitted: (_) => onConnect())),
      const SizedBox(width: 8),
      if (busy)
        SmallButton('Cancel', danger: true, onPressed: onCancel)
      else
        SmallButton('Retry', primary: true, onPressed: onConnect),
    ],
  );
}

/// Start Neovim on the address with the backend plugin (console, nvim-qt or headless), then connect;
/// and stop every headless Neovim.
class StartButtons extends StatelessWidget {
  const StartButtons({
    super.key,
    required this.starting,
    required this.enabled,
    required this.onStart,
    required this.onStopHeadless,
  });

  /// The kind being started, if any.
  final NvimKind? starting;
  final bool enabled;
  final ValueChanged<NvimKind> onStart;
  final VoidCallback onStopHeadless;

  static const _buttons = [
    (NvimKind.console, 'Start Neovim', Icons.play_arrow, 'nvim in its own console window'),
    (NvimKind.qt, 'Start nvim-qt', Icons.web_asset, 'the nvim-qt GUI'),
    (NvimKind.headless, 'Start headless', Icons.dns_outlined, 'nvim --headless, detached: no window, keeps running after the app quits'),
  ];

  Widget _start((NvimKind, String, IconData, String) b) {
    final (kind, label, icon, tip) = b;
    return Tooltip(
      message: tip,
      child: SmallButton(
        starting == kind ? 'Starting…' : label,
        icon: icon,
        onPressed: starting == null && enabled ? () => onStart(kind) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final b in _buttons) _start(b),
      Tooltip(
        message: 'stop every nvim --headless of this user (from the process list)',
        child: SmallButton('Stop headless', icon: Icons.stop, danger: true, onPressed: starting == null ? onStopHeadless : null),
      ),
    ],
  );
}

/// A neutral outcome under the address field.
class ConnectNotice extends StatelessWidget {
  const ConnectNotice(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: SelectableText(text, style: T.small),
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
