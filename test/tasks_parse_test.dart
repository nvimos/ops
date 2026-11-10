import 'package:flutter_test/flutter_test.dart';
import 'package:nvimos_poc/tasks/markdown.dart';
import 'package:nvimos_poc/tasks/model.dart';
import 'package:nvimos_poc/tasks/parse.dart';

// Shaped like nvimos-meta's files.
const taskFile = '''---
id: TASK-17
title: 'diagnostics: `<leader>ttt` disables all diagnostics (LSP, nvim-lint: vale,...'
status: Needs Test
assignee: []
created_date: '2026-11-02'
labels:
  - todo-ideas
  - ideas-october
dependencies: [TASK-3]
ordinal: 17000
---

## Description

diagnostics: `<leader>ttt` disables all
diagnostics everywhere.

- today: lua/genja/map-lsp.lua toggle_diagnostics
  continued on the next line

## Acceptance Criteria

- [x] #1 `<leader>ttt` in every buffer; tested (b829ae5)

## Verify

Hands-on checks.

- [x] zen z1/z2 turn diagnostics off
- [ ] try it by hand

## Original notes

```markdown
- [x] diagnostics: toggles
  - [ ] not a check of the task
```
''';

const proposal = '''# 11. aerial sidebar follows the file

Status: In Progress (backlog TASK-51)

## Why

Because.

## What Changes

- the sidebar follows :edit

## Impact

- Source: `todo-2026.md`
''';

const tasksMd = '''# Tasks

## 1. Build

- [x] 1.1 follow BufEnter
- [ ] 1.2 test it

## 2. Verify

- [ ] 2.1 tried by hand
''';

const deltaMd = '''## ADDED Requirements

### Requirement: Sidebar follows the file
The sidebar SHALL show the symbols of the file in the source window.

#### Scenario: edit another file
- **WHEN** the user runs :edit other.lua
- **THEN** the sidebar shows other.lua

## MODIFIED Requirements

### Requirement: Sidebar width
The sidebar SHALL be 30 columns.

## REMOVED Requirements

### Requirement: Manual refresh
''';

List<String> L(String s) => s.split('\n')..removeLast();

void main() {
  test('front matter: quoted title, block and inline lists, key lines', () {
    final f = parseFrontMatter(L(taskFile));
    expect(f.str('title'), 'diagnostics: `<leader>ttt` disables all diagnostics (LSP, nvim-lint: vale,...');
    expect(f.list('labels'), ['todo-ideas', 'ideas-october']);
    expect(f.list('dependencies'), ['TASK-3']);
    expect(f.list('assignee'), isEmpty);
    expect(f.keyLines['status'], 3);
    expect(f.end, 11);
  });

  test('task: fields, description blocks, acceptance, verify, original notes', () {
    final t = parseTask('backlog/tasks/task-17 - x.md', L(taskFile));
    expect([t.id, t.status, t.number, t.ordinal], ['TASK-17', 'Needs Test', 17, 17000]);
    expect(t.statusLine, 3);
    final d = t.description;
    expect((d[0] as Para).text, 'diagnostics: `<leader>ttt` disables all diagnostics everywhere.');
    expect((d[1] as Bullet).text, 'today: lua/genja/map-lsp.lua toggle_diagnostics continued on the next line');
    expect(t.acceptance.single.text, '#1 `<leader>ttt` in every buffer; tested (b829ae5)');
    expect(t.verify.map((c) => c.done), [true, false]);
    expect(t.verify.last.line, L(taskFile).indexOf('- [ ] try it by hand'));
    expect(t.originalNotes.length, 2);
    expect(t.archived, isFalse);
  });

  test('change: title, status, linked task, check groups, stage, deltas', () {
    final files = {
      'openspec/changes/11-aerial/proposal.md': L(proposal),
      'openspec/changes/11-aerial/tasks.md': L(tasksMd),
      'openspec/changes/11-aerial/specs/sidebar/spec.md': L(deltaMd),
      'openspec/changes/archive/2026-10-23-old/proposal.md': ['# old', '', 'Status: Done (backlog TASK-6)'],
    };
    final cs = parseChanges(files, {})..sort((a, b) => a.id.compareTo(b.id));
    final c = cs.firstWhere((c) => c.id == '11-aerial');
    expect(c.title, '11. aerial sidebar follows the file');
    expect([c.status, c.taskId, c.stage], ['In Progress', 'TASK-51', 'Active']);
    expect(c.checkGroups.map((g) => (g.$1, g.$2.length)), [('Build', 2), ('Verify', 1)]);
    expect(c.deltas.map((d) => (d.op, d.requirement.name)), [
      (DeltaOp.added, 'Sidebar follows the file'),
      (DeltaOp.modified, 'Sidebar width'),
      (DeltaOp.removed, 'Manual refresh'),
    ]);
    final added = c.deltas.first.requirement;
    expect(added.scenarios.single.steps, [
      '**WHEN** the user runs :edit other.lua',
      '**THEN** the sidebar shows other.lua',
    ]);
    final old = cs.firstWhere((c) => c.id == 'old');
    expect([old.archived, old.archiveDate, old.stage], [true, DateTime(2026, 10, 23), 'Completed']);
  });

  test('legacy: top-level checks with nested notes, untested and commits', () {
    final items = parseLegacy('todo-2027.md', [
      '# new setup 2027',
      '',
      '- [ ] minuet ghost text',
      '  - candidates: DeepSeek',
      '- [x] repos for plugins (2492965); untested',
      '',
      '## later',
      '- [ ] other',
    ]);
    expect(items.map((i) => (i.section, i.done, i.text)), [
      ('new setup 2027', false, 'minuet ghost text'),
      ('new setup 2027', true, 'repos for plugins (2492965); untested'),
      ('later', false, 'other'),
    ]);
    expect(items[0].notes, ['  - candidates: DeepSeek']);
    expect(
      [items[1].untested, items[1].commits, items[1].group],
      [
        true,
        ['2492965'],
        '2027',
      ],
    );
  });

  test('spec, milestones and backlog config', () {
    final spec = parseSpec(
      'sidebar',
      Doc('openspec/specs/sidebar/spec.md', [
        '# sidebar Specification',
        '## Purpose',
        'Symbols of the file.',
        '## Requirements',
        '### Requirement: Sidebar width',
        'The sidebar SHALL be 30 columns.',
      ]),
    );
    expect(spec.purpose, 'Symbols of the file.');
    expect(spec.requirements.single.name, 'Sidebar width');
    final ms = parseMilestones(['# Milestones', '## v2027 (2027-01-31)', '## v2026 (2026-11-30)']);
    expect(ms.map((m) => m.name), ['v2026', 'v2027']);
    final (statuses, name) = parseBacklogConfig([
      'project_name: "nvimos meta"',
      'statuses: ["To Do", "Needs Test", "Done"]',
    ]);
    expect(
      [name, statuses],
      [
        'nvimos meta',
        ['To Do', 'Needs Test', 'Done'],
      ],
    );
  });

  test('yamlScalar quotes what needs it', () {
    expect(yamlScalar('Done'), 'Done');
    expect(yamlScalar("it's: x"), "'it''s: x'");
  });
}
