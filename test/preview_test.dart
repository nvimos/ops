import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/state/preview.dart';

String untracked(String path) => path;

Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

/// A minimal `.lnk`: a header, a LinkInfo with a local path, then the working
/// folder and the arguments as ANSI string data.
Uint8List shortcut({required String target, required String args, required String dir}) {
  final header = ByteData(76)
    ..setUint32(0, 0x4c, Endian.little)
    ..setUint32(20, (1 << 1) | (1 << 4) | (1 << 5), Endian.little);
  final path = [...latin1.encode(target), 0];
  final info = ByteData(28 + path.length + 1)
    ..setUint32(0, 28 + path.length + 1, Endian.little)
    ..setUint32(4, 28, Endian.little)
    ..setUint32(8, 1, Endian.little)
    ..setUint32(16, 28, Endian.little)
    ..setUint32(24, 28 + path.length, Endian.little);
  final bytes = info.buffer.asUint8List()..setRange(28, 28 + path.length, path);
  List<int> string(String value) => [value.length, 0, ...latin1.encode(value)];
  return Uint8List.fromList([...header.buffer.asUint8List(), ...bytes, ...string(dir), ...string(args)]);
}

PreviewState previewOf(Map<String, Uint8List?> files) => PreviewState(
      root: () => 'C:/repo',
      read: (path, limit) async {
        final bytes = files[path.substring('C:/repo/'.length)];
        if (bytes == null) throw PathNotFoundException(path, const OSError('gone', 2));
        return bytes.length <= limit ? bytes : Uint8List.sublistView(bytes, 0, limit);
      },
    );

List<String> described(PreviewState state) => [
      for (final item in state.items)
        switch (item) {
          PreviewHeader(:final path) => '# $path',
          PreviewLine(:final number, :final text) => '$number $text',
          PreviewNote(:final text) => '($text)',
          PreviewPdf() => '[pages]',
          PreviewImage() => '[picture]',
          PreviewLaunch(:final text, :final program, :final facts) =>
            '[${program ? 'run' : 'open'}] $text${[for (final (label, value) in facts) ' | $label: $value'].join()}',
        },
    ];

void main() {
  test('a file shows its lines under its path', () async {
    final state = previewOf({'a.txt': text('one\ntwo\n')});
    await state.load([untracked('a.txt')]);
    expect(described(state), ['# a.txt', '1 one', '2 two']);
  });

  test('several files go one under the other, in the order given', () async {
    final state = previewOf({'a.txt': text('x'), 'b.txt': text('y')});
    await state.load([untracked('b.txt'), untracked('a.txt')]);
    expect(described(state), ['# b.txt', '1 y', '# a.txt', '1 x']);
  });

  test('a binary file is named and can be opened', () async {
    final state = previewOf({'a.bin': Uint8List.fromList([1, 2, 0, 3])});
    await state.load([untracked('a.bin')]);
    expect(described(state), ['# a.bin', '[open] binary file, 4 bytes']);
  });

  test('a PDF and a program are named, sized and openable', () async {
    final state = previewOf({
      'a.pdf': text('%PDF-1.7 ${'x' * 2048}'),
      'b.exe': Uint8List.fromList([0x4d, 0x5a, 0, 0]),
    });
    await state.load([untracked('a.pdf'), untracked('b.exe')]);
    expect(described(state), ['# a.pdf', '[open] PDF document, 2 KB', '# b.exe', '[run] Windows program, 4 bytes']);
  });

  test('with the renderer on a PDF also gets its pages', () async {
    final state = previewOf({'a.pdf': text('%PDF-1.7')})..renderPdf = true;
    await state.load([untracked('a.pdf')]);
    expect(described(state), ['# a.pdf', '[open] PDF document, 8 bytes', '[pages]']);
  });

  test('a shortcut shows its target, arguments and start folder', () async {
    final state = previewOf({'go.lnk': shortcut(target: r'C:\tools\app.exe', args: '--fast', dir: r'C:\tools')});
    await state.load([untracked('go.lnk')]);
    expect(described(state), [
      '# go.lnk',
      r'[open] Windows shortcut | Target: C:\tools\app.exe | Arguments: --fast | Start in: C:\tools',
    ]);
  });

  test('a broken shortcut falls back to a sentence', () async {
    final state = previewOf({'bad.lnk': Uint8List.fromList([0x4c, 0, 0, 0, 1, 2])});
    await state.load([untracked('bad.lnk')]);
    expect(described(state), ['# bad.lnk', '[open] Windows shortcut, unreadable']);
  });

  test('a folder, a missing file and an empty one say so', () async {
    final state = previewOf({'e.txt': text('')});
    await state.load([untracked('dir/'), untracked('gone.txt'), untracked('e.txt')]);
    expect(described(state), ['# dir/', '(folder)', '# gone.txt', '(not on disk)', '# e.txt', '(empty file)']);
  });

  test('a long file is cut and says so', () async {
    final lines = List.generate(PreviewState.maxLines + 5, (i) => 'l$i').join('\n');
    final state = previewOf({'big.txt': text(lines)});
    await state.load([untracked('big.txt')]);
    expect(state.items.whereType<PreviewLine>().length, PreviewState.maxLines);
    expect(described(state).last, '(the rest of the file is not shown)');
  });

  test('a newer load wins over an older one still reading', () async {
    final state = previewOf({'a.txt': text('old'), 'b.txt': text('new')});
    final older = state.load([untracked('a.txt')]);
    await state.load([untracked('b.txt')]);
    await older;
    expect(described(state), ['# b.txt', '1 new']);
  });

  test('a picture is named, sized and drawn', () async {
    final state = previewOf({'p.png': Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 1, 2])});
    await state.load([untracked('p.png')]);
    expect(described(state), ['# p.png', '[open] image, 7 bytes', '[picture]']);
  });
}
