import 'package:material_ui/material_ui.dart';

import '../backend/models.dart';
import '../state/hot_reload.dart';
import '../state/prefs.dart' show BackendKind;
import '../state/session.dart';
import 'debug_bar.dart';
import 'error_view.dart';
import 'nvim_logo.dart';
import 'theme.dart';
import 'widgets.dart';

/// Active Directory, current branch, Neovim's current file and cursor (live), connection state.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final cur = s.cursor;
    final dir = s.repo?.cwd ?? '';
    final head = s.repo?.head;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: Row(
        children: [
          if (dir.isNotEmpty) _Item(icon: Icons.folder_outlined, text: dir, tip: 'Active Directory'),
          if (head != null) _Item(icon: Icons.call_split, text: head, tip: 'Current branch'),
          Expanded(child: cur == null ? const SizedBox() : _Cursor(cursor: cur, root: s.repo?.root)),
          BackendIndicator(kind: s.kind, connected: s.conn == Conn.connected),
          const SizedBox(width: 8),
          _Connection(conn: s.conn, address: s.kind == BackendKind.local ? 'local' : s.address),
          if (const HotReload().available) ...[
            const SizedBox(width: 10),
            HotButtons(
              onReload: () => _hot(context, const HotReload().reload),
              onRestart: () => _hot(context, const HotReload().restart),
            ),
          ],
          const SizedBox(width: 10),
          const _DebugToggle(),
        ],
      ),
    );
  }

  static Future<void> _hot(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) showActionError(context, '$e');
    }
  }
}

/// Hot reload and hot restart: for the debug run (`make run`, `make live`) only;
/// the caller leaves them out of a release build.
class HotButtons extends StatelessWidget {
  const HotButtons({super.key, required this.onReload, required this.onRestart});

  final VoidCallback onReload;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconAction(icon: Icons.bolt, tooltip: 'Hot reload: the changed code, the state kept', onPressed: onReload),
      IconAction(icon: Icons.restart_alt, tooltip: 'Hot restart: start the app again', onPressed: onRestart),
    ],
  );
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.text, required this.tip});

  final IconData icon;
  final String text, tip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: Tooltip(
      message: tip,
      child: Row(
        children: [
          Icon(icon, size: 12, color: C.muted),
          const SizedBox(width: 4),
          Text(text, style: T.tiny),
        ],
      ),
    ),
  );
}

/// Neovim's current file (relative to the repo) and cursor.
class _Cursor extends StatelessWidget {
  const _Cursor({required this.cursor, required this.root});

  final Cursor cursor;
  final String? root;

  static String relative(String path, String? root) {
    var p = path.replaceAll('\\', '/');
    if (root != null && p.toLowerCase().startsWith('${root.toLowerCase()}/')) p = p.substring(root.length + 1);
    return p.isEmpty ? '[No Name]' : p;
  }

  @override
  Widget build(BuildContext context) => Text(
    '${relative(cursor.name, root)}  ${cursor.row}:${cursor.col + 1}',
    style: T.tiny,
    overflow: TextOverflow.ellipsis,
  );
}

/// Which backend the session runs on: a desktop for the local one (the app reads the repository
/// itself), Neovim's mark for Neovim. Faint while not connected.
class BackendIndicator extends StatelessWidget {
  const BackendIndicator({super.key, required this.kind, required this.connected});

  final BackendKind kind;
  final bool connected;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: kind == BackendKind.local ? 'Backend is local' : 'Backend is nvim',
    child: kind == BackendKind.local
        ? Icon(Icons.desktop_windows_outlined, size: 13, color: connected ? C.muted : C.faint)
        : NvimLogo(size: 12, dimmed: !connected),
  );
}

class _Connection extends StatelessWidget {
  const _Connection({required this.conn, required this.address});

  final Conn conn;
  final String address;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (conn) {
      Conn.connected => (C.green, address),
      Conn.connecting => (C.yellow, 'connecting to $address'),
      Conn.disconnected => (C.faint, 'not connected'),
    };
    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(label, style: T.tiny),
      ],
    );
  }
}

/// The bottom-right button that shows or hides the debug bar.
class _DebugToggle extends StatelessWidget {
  const _DebugToggle();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: debugBarVisible,
    builder: (context, on, _) => Tooltip(
      message: on ? 'Hide the debug bar' : 'Show the debug bar (what has the focus)',
      child: InkWell(
        onTap: () => debugBarVisible.value = !on,
        child: Icon(Icons.bug_report_outlined, size: 14, color: on ? C.yellow : C.muted),
      ),
    ),
  );
}
