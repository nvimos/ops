import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nvimos_poc/local/project_hints.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/repos.dart';
import 'package:nvimos_poc/state/session.dart';
import 'package:nvimos_poc/ui/dirs_view.dart';
import 'package:nvimos_poc/ui/theme.dart';

import 'local_browser_test.dart' show BlockingLister, dir;

/// A state over fixed hints and a crawl in memory; picking is recorded, not run.
class FixedRepos extends ReposState {
  FixedRepos(super.session, {required super.browser, required super.hints, required this.fixed});

  final List<ProjectHint> fixed;
  final picked = <String>[];

  @override
  Future<String?> pick(String dir) async {
    picked.add(dir);
    return null;
  }
}

void main() {
  late Session session;
  late FixedRepos state;
  late Prefs prefs;

  setUp(() {
    prefs = Prefs.memory()..rememberProject('C:/gone');
    session = Session(prefs: prefs);
    final fake = BlockingLister({
      'C:/fake': [dir('C:/fake/a'), dir('C:/fake/b')],
    }, repos: {'C:/fake/a', 'C:/fake/b'});
    state = FixedRepos(session, browser: fake.browser('C:/fake'), hints: ProjectHints(prefs: prefs), fixed: const []);
  });

  tearDown(() {
    state.dispose();
    session.dispose();
  });

  Future<void> mount(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      SessionScope(
        session: session,
        child: MaterialApp(theme: buildTheme(), home: Scaffold(body: DirsView(state: state))),
      ),
    );
    // the hints and the walk run on the real event loop: give them real turns
    for (var i = 0; i < 20 && state.entries.length < 3; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
  }

  testWidgets('the crawl results show, the crawl folder is named, a click picks', (t) async {
    await mount(t);
    expect(find.text('Repos'), findsOneWidget);
    expect(find.text('C:/fake'), findsOneWidget, reason: 'where the crawl walks from');
    expect(find.text('C:/fake/a'), findsOneWidget);
    expect(find.text('C:/fake/b'), findsOneWidget);

    await t.tap(find.text('C:/fake/b'));
    await t.pump();
    expect(state.picked, ['C:/fake/b']);
  });

  testWidgets('a stale hint is greyed, cannot be picked, and Remove takes it away', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await mount(t);
    expect(find.text('C:/gone'), findsOneWidget);
    expect(find.text('no longer a repository'), findsOneWidget);
    expect(t.widget<Text>(find.text('C:/gone')).style!.color, C.faint);

    await t.tap(find.text('C:/gone'));
    await t.pump();
    expect(state.picked, isEmpty);

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.text('C:/gone')));
    await t.pump();
    await t.tap(find.byTooltip('Remove this hint'));
    await t.pump();
    expect(find.text('C:/gone'), findsNothing);
    expect(prefs.recentProjects(), isEmpty);
  });

  testWidgets('no Neovim switch without an editor', (t) async {
    await mount(t);
    expect(find.text('New Neovim per directory'), findsNothing);
  });
}
