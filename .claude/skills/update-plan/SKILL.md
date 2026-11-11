---
name: update-plan
description: Update PLAN.md with what this session changed in the app - behavior, UI, keys, files under lib/. Edits PLAN.md only, commits nothing. Use when the user types /update-plan or asks to update the plan, PLAN.md or the spec with the session's changes.
---

# Update plan

Bring `PLAN.md` in line with what this session built or changed. The plan is the spec, so it
describes the app as it now is and must be after the change.

## 1. Collect the session's changes

- From the conversation: each feature or behavior change the user asked for and what was built.
- From `git diff` and new untracked files under `lib/`, `test/` and `Makefile`.
  - The working tree often holds the user's own uncommitted work from earlier sessions.
    Only take changes this session made; leave the rest out unless the user says otherwise.
- Skip pure refactors, tests and internal renames unless the plan names those files or types.

## 2. Find where each change belongs

- `grep -n` PLAN.md for the screen, mode, file or key the change touches; read that section
  before editing.
- UI behavior goes into its view's section (connect screen, mode rail, a mode).
- A new or renamed file under `lib/` goes into the file layout list, one line saying what it does.
- A new or changed key goes into the Keys table, and must match `keyTable` in
  `lib/ui/help_view.dart`. Report a mismatch rather than guessing which side is right.
- Replace statements the change made false (e.g. "retries forever"); do not leave the old and the
  new side by side.
- Sections marked _not strictly normative_ describe what is: update them when the facts changed.

## 3. Write in the plan's style

- Keep the fold markers (`<!-- {{{ name -->` ... `<!-- }}} -->`) intact; add new sections with them.
- List items: a topic line with one point per line underneath, indented two spaces. Use the
  `md-reformat` style, not "Topic: a, b; c" on one line.
- Concrete: button labels in quotes, keys in backticks, sizes and timeouts as numbers.
- Short lines; match the wording and wrap width of the lines around the edit.
- Edit with Python using `newline=''` (or the Edit tool) so the file keeps LF.

## 4. Idea files

- If a change shifts a main idea in `~/es/nvimos-meta/poc-nvim-backend/flutter*.md`, update that
  file too, but keep it vague: no buttons, no keys, no sizes. The plan wins where they disagree.

## 5. Report

- One line per section touched: the section name, then what changed in a few words.
- Mention anything skipped (the user's own uncommitted work, unclear changes) in one line.
- Do not commit; the user commits with the feature.
