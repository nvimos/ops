import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/prefs.dart' show BackendKind;
import 'package:nvimos_poc/ui/nvim_logo.dart';
import 'package:nvimos_poc/ui/status_bar.dart';
import 'package:nvimos_poc/ui/theme.dart';

Widget _app(Widget child) => MaterialApp(theme: buildTheme(), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('the backend indicator: a desktop for local, the Neovim mark for nvim, and says which', (t) async {
    await t.pumpWidget(_app(const BackendIndicator(kind: BackendKind.local, connected: true)));
    expect(find.byIcon(Icons.desktop_windows_outlined), findsOneWidget);
    expect(find.byTooltip('Backend is local'), findsOneWidget);

    await t.pumpWidget(_app(const BackendIndicator(kind: BackendKind.nvim, connected: true)));
    expect(find.byType(NvimLogo), findsOneWidget);
    expect(find.byTooltip('Backend is nvim'), findsOneWidget);
  });
}
