import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/preview_links.dart';

void main() {
  const root = 'C:/repo';
  const from = 'C:/repo/docs/guide.md';
  PreviewLink? link(String href) => resolveLink(href, from: from, root: root);

  test('web addresses go to the system', () {
    expect((link('https://docs.flutter.dev/x?a=1') as WebLink).url, 'https://docs.flutter.dev/x?a=1');
    expect(link('http://example.com'), isA<WebLink>());
    expect(link('mailto:someone@example.com'), isA<WebLink>());
  });

  test('a markdown link resolves against the document folder, relative to the repo', () {
    expect((link('other.md') as DocumentLink).path, 'docs/other.md');
    expect((link('../README.md') as DocumentLink).path, 'README.md');
    expect((link('./sub/a.markdown#part') as DocumentLink).path, 'docs/sub/a.markdown');
    expect((link('my%20notes.md') as DocumentLink).path, 'docs/my notes.md');
    expect((link('../../outside.md') as DocumentLink).path, 'C:/outside.md', reason: 'outside the repo: absolute');
    expect((link(r'D:\notes\x.md') as DocumentLink).path, 'D:/notes/x.md');
  });

  test('another local file is opened; an anchor in the same document does nothing', () {
    expect((link('../assets/icon/ops.svg') as FileLink).path, 'C:/repo/assets/icon/ops.svg');
    expect(link('#heading'), isNull);
  });

  test('an HTML page links resolved file: URLs: a page opens in the preview, an in-page anchor does nothing', () {
    expect((link('file:///C:/repo/docs/page.html#part') as DocumentLink).path, 'docs/page.html');
    expect((link('file:///C:/repo/index.htm') as DocumentLink).path, 'index.htm');
    expect(link('file:///C:/repo/docs/#top'), isNull);
    expect((link('file:///C:/repo/docs/my%20pic.png') as FileLink).path, 'C:/repo/docs/my pic.png');
    expect((link('page.html') as DocumentLink).path, 'docs/page.html', reason: 'markdown linking to HTML');
  });

  test('the repo root may end in a slash and differ in case', () {
    expect((resolveLink('b.md', from: 'c:/Repo/a.md', root: 'C:/repo/') as DocumentLink).path, 'b.md');
  });
}
