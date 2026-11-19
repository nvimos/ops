import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/local/editors.dart';
import 'package:nvimos_poc/local/system.dart';

/// A fake machine: `which` answers from [path], `exists` from [files], and the
/// environment is just a map. No process runs and no file is read unless a test
/// asks for it.
Editors machine({
  Map<String, String> path = const {},
  Set<String> files = const {},
  Map<String, String> env = const {},
  String? gitEditor,
  List<String> nvimQt = const [],
  String? saved,
}) => Editors(
  savedCommand: () => saved,
  which: (exe) async => path[exe],
  exists: (path) async => files.contains(path),
  gitEditor: () async => gitEditor,
  nvimQtCandidates: () async => nvimQt,
  env: Env(env),
);

List<String> ids(List<EditorOption> options) =>
    options.map((option) => option.id).toList();

void main() {
  group('splitCommand', () {
    test('a plain command becomes words', () {
      expect(Editors.splitCommand('code --goto {file}'), [
        'code',
        '--goto',
        '{file}',
      ]);
    });

    test('a quoted path with spaces stays one word', () {
      expect(
        Editors.splitCommand(
          '"C:\\Program Files\\Neovim\\bin\\nvim-qt.exe" -- {file}',
        ),
        ['C:\\Program Files\\Neovim\\bin\\nvim-qt.exe', '--', '{file}'],
      );
    });

    test('runs of spaces and tabs do not make empty words', () {
      expect(Editors.splitCommand('  nvim \t  {file}  '), ['nvim', '{file}']);
    });

    test('an empty template has no words', () {
      expect(Editors.splitCommand(''), isEmpty);
      expect(Editors.splitCommand('   '), isEmpty);
    });
  });

  group('expand', () {
    test('{file} is replaced and the template split', () {
      expect(Editors.expand('code --goto {file}', file: 'lib/ui/shell.dart'), [
        'code',
        '--goto',
        'lib/ui/shell.dart',
      ]);
    });

    test('a file with spaces stays one argument', () {
      expect(
        Editors.expand(
          'nvim {file}',
          file: r'C:\My Repo\lib\a b.dart',
          line: 7,
        ),
        ['nvim', r'C:\My Repo\lib\a b.dart'],
      );
    });

    test('{line} is the line, or 1 when the caller has none', () {
      expect(
        Editors.expand('code --goto {file}:{line}', file: 'a.dart', line: 42),
        ['code', '--goto', 'a.dart:42'],
      );
      expect(Editors.expand('code --goto {file}:{line}', file: 'a.dart'), [
        'code',
        '--goto',
        'a.dart:1',
      ]);
    });

    test('a template without {file} gets the path appended', () {
      expect(Editors.expand('code', file: 'a.dart'), ['code', 'a.dart']);
    });

    test('a quoted executable path survives expand', () {
      expect(
        Editors.expand(
          '"C:\\Program Files\\Neovim\\bin\\nvim-qt.exe" {file}',
          file: 'a.dart',
        ),
        ['C:\\Program Files\\Neovim\\bin\\nvim-qt.exe', 'a.dart'],
      );
    });

    test('exeOf is the first word, quoted or not', () {
      expect(
        Editors.exeOf('"C:\\Tools\\code.cmd" {file}'),
        'C:\\Tools\\code.cmd',
      );
      expect(Editors.exeOf(''), isNull);
    });
  });

  group('detection order', () {
    test('the saved choice comes first', () async {
      final found = await machine(
        saved: '"C:\\Tools\\mine.exe" {file}',
        path: {'code': 'C:\\bin\\code.cmd'},
      ).detect();

      expect(ids(found).first, 'saved');
      expect(found.first.command, '"C:\\Tools\\mine.exe" {file}');
      expect(ids(found), contains('code'));
    });

    test('nvim-qt on PATH beats every known editor', () async {
      final found = await machine(
        path: {'nvim-qt': 'C:\\bin\\nvim-qt.exe', 'code': 'C:\\bin\\code.cmd'},
      ).detect();
      expect(ids(found), ['nvim-qt', 'code', 'notepad']);
    });

    test('nvim-qt found in Program Files when it is not on PATH', () async {
      final exe = 'C:\\Program Files\\neovim-qt 0.2\\bin\\nvim-qt.exe';
      final found = await machine(
        nvimQt: [exe],
        files: {exe},
        path: {'code': 'C:\\bin\\code.cmd'},
      ).detect();
      expect(ids(found), ['nvim-qt', 'code', 'notepad']);
      expect(found.first.path, exe);
    });

    test(
      'a resolvable git var GIT_EDITOR comes before VISUAL and EDITOR',
      () async {
        final found = await machine(
          gitEditor: '"C:\\Program Files\\Neovim\\bin\\nvim.exe" --wait',
          files: {'C:\\Program Files\\Neovim\\bin\\nvim.exe'},
          env: {'VISUAL': 'code', 'EDITOR': 'notepad'},
          path: {
            'code': 'C:\\bin\\code.cmd',
            'notepad': 'C:\\Windows\\notepad.exe',
          },
        ).detect();
        expect(ids(found), ['git', 'visual', 'editor', 'code']);
        expect(found[2].command, 'notepad {file}');
        expect(
          found.first.command,
          '"C:\\Program Files\\Neovim\\bin\\nvim.exe" --wait {file}',
        );
      },
    );

    test('git var reporting vi is skipped when vi is not on PATH', () async {
      final found = await machine(
        gitEditor: 'vi',
        path: {'code': 'C:\\bin\\code.cmd'},
      ).detect();
      expect(ids(found), ['code', 'notepad']);
    });

    test('git var reporting vi is kept when vi does exist', () async {
      final found = await machine(
        gitEditor: 'vi',
        path: {'vi': 'C:\\tools\\vi.exe'},
      ).detect();
      expect(ids(found).first, 'git');
    });

    test('VISUAL comes before EDITOR', () async {
      final found = await machine(
        env: {'VISUAL': 'code', 'EDITOR': 'nvim'},
        path: {'code': 'C:\\bin\\code.cmd', 'nvim': 'C:\\bin\\nvim.exe'},
      ).detect();
      expect(ids(found), ['visual', 'editor', 'code', 'nvim', 'notepad']);
    });

    test('an unresolvable VISUAL or EDITOR is skipped', () async {
      final found = await machine(
        env: {'VISUAL': 'no-such-editor', 'EDITOR': 'C:\\gone\\editor.exe'},
        path: {'code': 'C:\\bin\\code.cmd'},
      ).detect();
      expect(ids(found), ['code', 'notepad']);
    });

    test('known editors keep the PLAN.md order', () async {
      final found = await machine(
        path: {
          'code': 'C:\\bin\\code.cmd',
          'nvim': 'C:\\bin\\nvim.exe',
          'gvim': 'C:\\bin\\gvim.exe',
          'notepad++': 'C:\\bin\\notepad++.exe',
          'zed': 'C:\\bin\\zed.exe',
          'hx': 'C:\\bin\\hx.exe',
          'subl': 'C:\\bin\\subl.exe',
          'cursor': 'C:\\bin\\cursor.exe',
          'idea64': 'C:\\bin\\idea64.exe',
        },
      ).detect();
      expect(ids(found), [
        'code',
        'nvim',
        'gvim',
        'notepad++',
        'zed',
        'hx',
        'subl',
        'cursor',
        'idea64',
        'notepad',
      ]);
    });

    test('nothing found still offers Notepad', () async {
      final found = await machine().detect();
      expect(ids(found), ['notepad']);
      expect(found.single.detected, isTrue);
    });

    test('the first detected editor is the chosen one', () async {
      final editors = machine(path: {'code': 'C:\\bin\\code.cmd'});
      expect(await editors.chosen(), '"C:\\bin\\code.cmd" {file}');
    });
  });
}
