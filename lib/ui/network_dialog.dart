import 'package:material_ui/material_ui.dart';

import '../rpc/stats.dart';
import 'theme.dart';
import 'widgets.dart';

/// The slowest requests of this run and the ones still waiting, each with what it was
/// (`nvimos.git.diff_file`), which functions of the app asked, and its first argument (a path, a
/// branch), so slow calls can be told apart and traced to their cause. Opened from the debug bar's
/// network monitor. A snapshot: Refresh reads the numbers again. Session data only, never stored.
class NetworkDialog extends StatefulWidget {
  const NetworkDialog({super.key, this.stats});

  final RpcStats? stats;

  @override
  State<NetworkDialog> createState() => _NetworkDialogState();
}

class _NetworkDialogState extends State<NetworkDialog> {
  RpcStats get _stats => widget.stats ?? RpcStats.instance;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final waiting = _stats.waiting, slow = _stats.slowestCalls;
    return SelectionArea(
      child: AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Requests to Neovim', style: T.title),
        content: SizedBox(
          width: (size.width * .7).clamp(420, 1000),
          height: size.height * .6,
          child: ListView(
            children: [
              if (waiting.isNotEmpty) ..._section('Waiting now', waiting, waiting: true),
              ..._section('Slowest in this session', slow, waiting: false),
              const SizedBox(height: 8),
              const Text('Only kept while the app runs.', style: T.tiny),
            ],
          ),
        ),
        actions: [
          SelectionContainer.disabled(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SmallButton('Refresh', onPressed: () => setState(() {})),
                const SizedBox(width: 8),
                SmallButton('Close', primary: true, onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<RpcCall> calls, {required bool waiting}) => [
    Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(title, style: T.tiny),
    ),
    if (calls.isEmpty) const Text('none yet', style: T.body),
    for (final c in calls) CallRow(call: c, now: _stats.now, waiting: waiting),
  ];
}

/// One request: how long it took (or has waited), what it is, who asked, when.
class CallRow extends StatelessWidget {
  const CallRow({super.key, required this.call, required this.now, required this.waiting});

  final RpcCall call;
  final Duration now;
  final bool waiting;

  static const _code = TextStyle(fontSize: 12, fontFamily: mono, color: C.text);
  static const _faint = TextStyle(fontSize: 11, fontFamily: mono, color: C.faint);

  @override
  Widget build(BuildContext context) {
    final took = waiting ? now - call.sentAt : call.took!;
    final o = call.origin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              fmtDuration(took),
              textAlign: TextAlign.right,
              style: _code.copyWith(color: waiting || took.inMilliseconds >= 500 ? C.red : C.yellow),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(call.ok ? '${o.what}  ${o.detail}' : '${o.what}  ${o.detail}  (failed)', style: _code),
                Text('${o.from}   sent at ${fmtDuration(call.sentAt)}', style: _faint),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "412 ms", "3.2 s", "2 min 5 s".
String fmtDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
  if (d.inSeconds < 60) return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  return '${d.inMinutes} min ${d.inSeconds % 60} s';
}

Future<void> showNetworkDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const NetworkDialog());
