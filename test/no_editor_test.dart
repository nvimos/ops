import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/changes.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/ui/status_bar.dart';
import 'package:nvimos_poc/ui/tasks/legacy_detail.dart';
import 'package:nvimos_poc/ui/theme.dart';

LegacyItem item() => LegacyItem(file: 'todo.md', section: 'now', line: 3, done: false, text: 'a note', notes: const []);

Widget host(Widget child) => MaterialApp(theme: buildTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('without an editor a panel has no Open in Neovim button, with one it has', (t) async {
    Widget panel({VoidCallback? onOpen}) => LegacyDetail(item: item(), onClose: () {}, onPromote: () {}, onOpen: onOpen);

    await t.pumpWidget(host(panel()));
    expect(find.text('Open in Neovim'), findsNothing);
    expect(find.text('Promote to task'), findsOneWidget);

    await t.pumpWidget(host(panel(onOpen: () {})));
    expect(find.text('Open in Neovim'), findsOneWidget);
  });

  test('a session without an editor has none, and the open calls say nothing instead of failing', () async {
    final s = Session();
    addTearDown(s.dispose);
    expect(s.hasEditor, isFalse);
    expect(await s.runEditor((e) => e.open('a.txt', 1)), 'not connected');

    final st = ChangesState(s)..selected = 'a.txt';
    addTearDown(st.dispose);
    expect(await st.openLine(3, isOld: false), isNull);
  });

  testWidgets('the status bar names a local session "local", not a Neovim address', (t) async {
    final s = Session(port: 7777)..kind = BackendKind.local;
    addTearDown(s.dispose);
    s.conn = Conn.connected;
    await t.pumpWidget(SessionScope(session: s, child: host(const StatusBar())));
    expect(find.text('local'), findsOneWidget);
    expect(find.textContaining('7777'), findsNothing);
  });
}
