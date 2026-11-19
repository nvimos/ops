import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/browser.dart';
import 'package:nvimos_poc/local/system.dart';

/// A directory tree in memory: [tree] maps a directory to its subdirectories,
/// [repos] are the ones holding a `.git`. A listing in [blocked] waits for its
/// completer, so a test can act while the walk is in the middle.
class BlockingLister implements DirectoryLister {
  BlockingLister(this.tree, {this.repos = const {}});

  final Map<String, List<DirEntry>> tree;
  final Set<String> repos;
  final Map<String, Completer<void>> blocked = {};
  final List<String> listed = [];

  static String _clean(String path) => path.replaceAll(r'\', '/');

  @override
  Future<List<DirEntry>> list(String path) async {
    final clean = _clean(path);
    listed.add(clean);
    final gate = blocked[clean];
    if (gate != null) await gate.future;
    return tree[clean] ?? const [];
  }

  @override
  Future<bool> exists(String path) async {
    final clean = _clean(path);
    return clean.endsWith('/.git') && repos.contains(clean.substring(0, clean.length - 5));
  }

  RepoBrowser browser(String start, {void Function(ScanReport)? onReport}) => RepoBrowser(
        startDirectory: start,
        lister: this,
        onReport: onReport,
        env: const Env({}, isWindows: true),
      );
}

DirEntry dir(String path) => DirEntry(path, isDirectory: true);

/// Let the walk run until [done] holds, without a real timer racing it.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await pumpEventQueue();
  }
  expect(done(), isTrue);
}

void main() {
  test('the first repositories show before the scan ends', () async {
    final fake = BlockingLister({
      'C:/fake': [dir('C:/fake/a'), dir('C:/fake/slow')],
      'C:/fake/slow': [dir('C:/fake/slow/b')],
    }, repos: {'C:/fake/a', 'C:/fake/slow/b'});
    fake.blocked['C:/fake/slow'] = Completer<void>();
    final browser = fake.browser('C:/fake');
    addTearDown(browser.dispose);

    final scan = browser.scan();
    await until(() => fake.listed.contains('C:/fake/slow'));
    expect(browser.scanning, isTrue);
    expect(browser.repos, ['C:/fake/a']);

    fake.blocked['C:/fake/slow']!.complete();
    await scan;
    expect(browser.scanning, isFalse);
    expect(browser.repos, ['C:/fake/a', 'C:/fake/slow/b']);
  });

  test('up during a scan cancels it: the old walk lists nothing more', () async {
    final reports = <ScanReport>[];
    final fake = BlockingLister({
      'C:/fake': [dir('C:/fake/other')],
      'C:/fake/deep': [dir('C:/fake/deep/x')],
      'C:/fake/deep/x': [dir('C:/fake/deep/x/y')],
      'C:/fake/deep/x/y': [dir('C:/fake/deep/x/y/z')],
    }, repos: {'C:/fake/other'});
    fake.blocked['C:/fake/deep/x'] = Completer<void>();
    final browser = fake.browser('C:/fake/deep', onReport: reports.add);
    addTearDown(browser.dispose);

    final old = browser.scan();
    await until(() => fake.listed.contains('C:/fake/deep/x'));
    final up = browser.up();
    fake.blocked['C:/fake/deep/x']!.complete();
    await Future.wait([old, up]);
    await browser.idle();

    expect(fake.listed, isNot(contains('C:/fake/deep/x/y')));
    expect(browser.directory, 'C:/fake');
    expect(browser.repos, ['C:/fake/other']);
    expect(browser.scanning, isFalse);
    expect(reports.map((report) => report.directory), ['C:/fake']);
  });

  test('a finished scan reports the slowest and the widest listings', () async {
    ScanReport? report;
    final fake = BlockingLister({
      'C:/fake': [dir('C:/fake/a'), dir('C:/fake/b'), dir('C:/fake/c')],
      'C:/fake/a': [dir('C:/fake/a/1'), dir('C:/fake/a/2')],
    });
    final browser = fake.browser('C:/fake', onReport: (r) => report = r);
    addTearDown(browser.dispose);
    await browser.scan();
    expect(report, isNotNull);
    expect(report!.widest.first.path, 'C:/fake');
    expect(report!.widest.first.entries, 3);
    expect(report!.slowest, isNotEmpty);
    expect(report!.detail, contains('slowest listings:'));
    expect(report!.detail, contains('widest directories:'));
  });

  test('a link is never walked', () async {
    final fake = BlockingLister({
      'C:/fake': [
        const DirEntry('C:/fake/junction', isDirectory: true, isLink: true),
        const DirEntry('C:/fake/f.txt', isDirectory: false),
      ],
    });
    final browser = fake.browser('C:/fake');
    addTearDown(browser.dispose);
    await browser.scan();
    expect(fake.listed, ['C:/fake']);
  });
}
