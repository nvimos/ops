import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/tasks/workspace.dart';
import 'package:nvimos_poc/ui/tasks/rows.dart';
import 'package:nvimos_poc/ui/tasks/tasks_nav.dart';
import 'package:nvimos_poc/ui/tasks/tasks_view.dart';
import 'package:nvimos_poc/ui/theme.dart';
import 'package:nvimos_poc/ui/widgets.dart';

import '../test/support/snappy.dart';
import '../test/support/temp_dirs.dart';

/// Snappy UI checks on the real app (`make snappy-app`, OpenSpec change `ops-snappy-ui-checks`):
/// the Tasks mode in a profile build on Windows, on the project snapshot, with the frame timings
/// the engine reports (build and raster time per frame). Each view and interaction is one key,
/// `<view>/<interaction>`; the driver (`test_driver/integration_test.dart`) records the run and
/// compares it with the baseline. The widget-count checks stay in `test/snappy_tasks_test.dart`.
///
/// Local mode (no Neovim): the folder is opened with the local backend, as `ops.exe <folder>` does.

const views = ['Inbox', 'Open tasks', 'To Do', 'In Progress', 'Needs Test', 'Done', 'Dropped', 'All tasks', 'Changes', 'Milestones'];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('snappy app: frame timings of every Tasks view', (t) async {
    // Cleaned up in tear-downs, so a failing run leaves nothing in %TEMP% either.
    final appData = await Directory.systemTemp.createTemp('nvimos_appdata_');
    Prefs.baseOverride = appData.path;
    addTearDown(() {
      Prefs.baseOverride = null;
      try {
        appData.deleteSync(recursive: true);
      } on FileSystemException {
        // in use: the OS temp cleanup gets it
      }
    });
    addTearDown(removeTempDirs); // the unpacked fixture
    final repo = await SnappyFixture.load().unpack();
    final s = Session(prefs: Prefs.memory());
    addTearDown(s.dispose);
    await s.openFolder(repo.path);
    final ws = Workspace(s);
    addTearDown(ws.dispose);
    for (var i = 0; i < 300 && !(ws.loaded && !ws.loading); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(ws.loaded, isTrue, reason: 'the fixture loads in local mode within 30 s');

    final key = GlobalKey<TasksViewState>();
    await t.pumpWidget(
      SessionScope(
        session: s,
        child: MaterialApp(theme: buildTheme(), home: Scaffold(body: TasksView(key: key, ws: ws))),
      ),
    );
    await settle(t);
    final b = key.currentState!.browser;
    final rows = find.descendant(of: find.byType(TaskRows), matching: find.byType(HoverRow));

    /// One measured interaction: its frames, plus the quiet frames after it until the engine has
    /// reported their timings (it sends them in batches).
    Future<void> measure(String name, Future<void> Function() input) =>
        binding.watchPerformance(() async {
          await input();
          await settle(t);
        }, reportKey: name);

    for (final view in views) {
      final entry = find.byWidgetPredicate((w) => w is NavItem && w.label == view);
      if (entry.evaluate().isEmpty) continue;
      await measure('$view/switch', () => t.tap(entry.first));
      await press(t, LogicalKeyboardKey.arrowRight); // from the sidebar into the list
      await settle(t);
      if (b.rows().every((r) => r.isHeader)) continue;
      await measure('$view/open', () => press(t, LogicalKeyboardKey.keyJ));
      await measure('$view/move', () async {
        for (var i = 0; i < 5; i++) {
          await press(t, LogicalKeyboardKey.keyJ);
          await t.pump(const Duration(milliseconds: 60)); // key repeat pace
        }
      });
      final n = rows.evaluate().length;
      if (n > 0) await measure('$view/click', () => t.tap(rows.at(n > 1 ? 1 : 0)));
      if (b.selected == null) {
        await press(t, LogicalKeyboardKey.keyJ);
        await settle(t);
      }
      await measure('$view/detail', () => press(t, LogicalKeyboardKey.arrowRight));
      await press(t, LogicalKeyboardKey.arrowLeft);
      await settle(t);
    }

    await t.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// A key press. The physical key is named: in a profile build keys have no debug names, which is
/// how `sendKeyEvent` finds the physical key on its own.
Future<void> press(WidgetTester t, LogicalKeyboardKey key) => t.sendKeyEvent(key, physicalKey: _physical[key]!);

final _physical = {
  LogicalKeyboardKey.keyJ: PhysicalKeyboardKey.keyJ,
  LogicalKeyboardKey.arrowRight: PhysicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowLeft: PhysicalKeyboardKey.arrowLeft,
};

/// Frames until the interaction has drawn and the engine has sent its timings: the engine batches
/// frame timings, so a short real wait and one more frame flush them.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  await t.pump();
}
