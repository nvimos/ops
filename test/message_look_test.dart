import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/ui/error_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

void main() {
  testWidgets('a message is dark, has an X that closes it, and floats above the bottom bar', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(
              body: SizedBox.expand(),
              bottomNavigationBar: SizedBox(key: Key('bar'), height: 24),
            );
          },
        ),
      ),
    );
    showActionError(ctx, 'something failed');
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('something failed'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    final material = t.widget<Material>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);
    expect(material.color, C.surface2);

    final message = t.getRect(find.byType(SnackBar));
    final bottomBar = t.getRect(find.byKey(const Key('bar')));
    expect(message.bottom, lessThanOrEqualTo(bottomBar.top));

    await t.tap(find.byIcon(Icons.close));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(SnackBar), findsNothing);
  });
}
