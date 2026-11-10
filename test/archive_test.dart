import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/tasks/archive.dart';
import 'package:nvimos_poc/tasks/markdown.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/parse.dart';

const delta = [
  '## ADDED Requirements',
  '',
  '### Requirement: Sidebar follows the file',
  'The sidebar SHALL follow :edit.',
  '',
  '#### Scenario: edit',
  '- **WHEN** :edit x',
  '- **THEN** it shows x',
  '',
  '## MODIFIED Requirements',
  '',
  '### Requirement: Sidebar width',
  'The sidebar SHALL be 40 columns.',
  '',
  '## REMOVED Requirements',
  '',
  '### Requirement: Manual refresh',
];

const spec = [
  '# sidebar Specification',
  '',
  '## Purpose',
  '',
  'Symbols of the file.',
  '',
  '## Requirements',
  '',
  '### Requirement: Sidebar width',
  'The sidebar SHALL be 30 columns.',
  '',
  '### Requirement: Manual refresh',
  'The user SHALL refresh with R.',
];

void main() {
  test('merge adds, modifies and removes requirements in an existing spec', () {
    final out = mergeDeltas(spec, 'sidebar', '11-aerial', parseDeltas('sidebar', delta));
    final s = parseSpec('sidebar', Doc('x', out));
    expect(s.purpose, 'Symbols of the file.');
    expect(s.requirements.map((r) => (r.name, r.text)), [
      ('Sidebar width', 'The sidebar SHALL be 40 columns.'),
      ('Sidebar follows the file', 'The sidebar SHALL follow :edit.'),
    ]);
    expect(s.requirements.last.scenarios.single.steps.length, 2);
    expect(out.last, isNotEmpty); // the file ends with one newline, written by Neovim
    for (var i = 1; i < out.length; i++) {
      expect(out[i].isEmpty && out[i - 1].isEmpty, isFalse, reason: 'double blank line at $i');
    }
  });

  test('merge into a missing spec creates one', () {
    final added = parseDeltas('sidebar', delta).where((d) => d.op == DeltaOp.added).toList();
    final out = mergeDeltas(null, 'sidebar', '11-aerial', added);
    expect(out.first, '# sidebar Specification');
    final s = parseSpec('sidebar', Doc('x', out));
    expect(s.requirements.single.name, 'Sidebar follows the file');
    expect(parseSections(out).map((s) => s.title), contains('Requirements'));
  });

  test('a spec without a Requirements section gets one', () {
    final out = mergeDeltas(
      ['# x Specification', '', '## Purpose', '', 'p.'],
      'x',
      'c',
      parseDeltas('x', delta.sublist(0, 8)),
    );
    expect(parseSpec('x', Doc('x', out)).requirements.single.name, 'Sidebar follows the file');
  });

  test('archive dir is dated', () {
    final c = parseChanges({
      'openspec/changes/11-aerial/proposal.md': ['# a'],
    }, {}).single;
    expect(archiveDir(c, DateTime(2026, 11, 3)), 'openspec/changes/archive/2026-11-03-11-aerial');
  });
}
