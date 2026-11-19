
import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/paths.dart';
import 'package:nvimos_poc/local/project_hints.dart';
import 'package:nvimos_poc/state/prefs.dart';
import 'package:nvimos_poc/state/repos.dart';
import 'package:nvimos_poc/state/session.dart';

import 'local_browser_test.dart' show BlockingLister, dir;
import 'session_test.dart' show until;
import 'support/nvim.dart';

String norm(String p) => canonicalPath(p).toLowerCase();

void main() {
  test('the list is the hints first (stale ones last of them), then what the crawl found', () async {
    final live = await makeRepo();
    final prefs = Prefs.memory()
      ..rememberProject('C:/no/longer/here')
      ..rememberProject(live.path);
    final fake = BlockingLister({
      'C:/fake': [dir('C:/fake/a'), dir('C:/fake/b')],
    }, repos: {'C:/fake/a', 'C:/fake/b'});
    final s = Session(prefs: prefs);
    addTearDown(s.dispose);
    final d = ReposState(s, browser: fake.browser('C:/fake'), hints: ProjectHints(prefs: prefs));
    addTearDown(d.dispose);

    await until(() => d.entries.length == 4 && !d.browser.scanning);
    expect(d.entries.map((e) => e.source), ['recent', 'recent', 'found', 'found']);
    expect(norm(d.entries[0].path), norm(live.path));
    expect(d.entries[0].stale, isFalse);
    expect(d.entries[1].stale, isTrue, reason: 'a hint that is no repository is greyed, not dropped');
    expect(d.entries.skip(2).map((e) => e.path), ['C:/fake/a', 'C:/fake/b']);

    d.setFilter('fake/b');
    expect(d.shown, ['C:/fake/b']);
    d.setFilter('');

    // Remove forgets the stale hint for good
    d.remove('C:/no/longer/here');
    expect(d.entries.map((e) => e.path).contains('C:/no/longer/here'), isFalse);
    expect(prefs.recentProjects().map(norm), [norm(live.path)]);
  });

  test('with no Neovim: the list needs none, and picking a repository opens it locally', () async {
    final repo = await makeRepo();
    final prefs = Prefs.memory();
    final fake = BlockingLister({'C:/fake': const []});
    final s = Session(prefs: prefs);
    addTearDown(s.dispose);
    addTearDown(s.disconnect);
    final d = ReposState(s, browser: fake.browser('C:/fake'), hints: ProjectHints(prefs: prefs, active: repo.path));
    addTearDown(d.dispose);

    await until(() => d.entries.isNotEmpty);
    expect(d.entries.single.source, 'active');
    expect(s.conn, Conn.disconnected);

    expect(await d.pick(repo.path), isNull);
    expect(s.conn, Conn.connected);
    expect(s.kind, BackendKind.local);
    expect(norm(d.active!), norm(repo.path));
    expect(prefs.recentProjects().map(norm), [norm(repo.path)]);
    expect(await d.openingTarget(), OpenTarget.tasks);
  });

  test('a folder git refuses is an error, and the crawl stops offering it', () async {
    final prefs = Prefs.memory();
    final fake = BlockingLister({
      'C:/fake': [dir('C:/fake/gone')],
    }, repos: {'C:/fake/gone'});
    final s = Session(prefs: prefs);
    addTearDown(s.dispose);
    final d = ReposState(s, browser: fake.browser('C:/fake'), hints: ProjectHints(prefs: prefs));
    addTearDown(d.dispose);
    await until(() => d.entries.length == 1 && !d.browser.scanning);

    expect(await d.pick('C:/fake/gone'), isNotNull);
    expect(s.conn, Conn.disconnected);
    expect(d.entries, isEmpty);
  });
}
