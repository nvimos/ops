import 'package:flutter/gestures.dart' show kSecondaryButton;
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
    // Each path is two columns: the folder 'C:/fake/' (the same on both rows) and the base name.
    expect(find.text('C:/fake/'), findsNWidgets(2));
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(t.widget<Text>(find.text('b')).style!.color, C.folder, reason: 'a directory name takes the folder amber');

    await t.tap(find.text('b'));
    await t.pump();
    expect(state.picked, ['C:/fake/b']);
  });

  testWidgets('a stale hint is greyed, cannot be picked, and Remove takes it away', (t) async {
    await mount(t);
    // The path is two columns: the folder 'C:/' and the base name 'gone'.
    expect(find.text('gone'), findsOneWidget);
    expect(find.text('no longer a repository'), findsOneWidget);
    expect(t.widget<Text>(find.text('gone')).style!.color, C.faint);

    await t.tap(find.text('gone'));
    await t.pump();
    expect(state.picked, isEmpty);

    // Remove lives in the row's menu now.
    await t.tapAt(t.getCenter(find.text('gone')), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(find.text('gone'), findsNothing);
    expect(prefs.recentProjects(), isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('no Neovim switch without an editor', (t) async {
    await mount(t);
    expect(find.text('New Neovim per directory'), findsNothing);
  });
}
