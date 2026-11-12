import 'package:material_ui/material_ui.dart';

import '../backend/models.dart';
import '../state/session.dart';
import 'theme.dart';

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
          _Connection(conn: s.conn, address: s.address),
        ],
      ),
    );
  }
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
