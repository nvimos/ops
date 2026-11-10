# nvimos-poc-frontend, one-shot v1: state, decisions, look and feel

Snapshot of the first pass (2026-11-10), written to pick the work up again later. PLAN.md has
the plan and step list, README.md how to run it. This file holds everything else: why it is built
this way, how it looks and behaves, how the work was done and verified, what is missing, and what
was learned.

## What it is

A native Windows Flutter app (exe `nvimos_poc`) over a running Neovim. It is meant for the
morning after agents worked overnight:

- **Pull request:** review an agent's branch against `main` like a GitHub PR, and click any line
  to see it in Neovim;
- **Changes:** stage hunks and commit, like GitHub Desktop;
- **Tasks ("Folio"):** a Linear-style workspace over the repo's OpenSpec and Backlog.md files.
  Triage in the evening, verify and archive in the morning.

All editor, git and file state comes from the backend plugin `~/es/nvimos-poc-backend` (protocol in
its README). The app runs no git and touches no files itself; everything goes through Neovim.

Sources of the requirements, all in `~/es/nvimos-meta/poc-nvim-backend/`:

- `flutter.md`: the review app;
- `flutter-project-man.md`: Folio, rewritten from the Grok conversation "OpenSpec Inquiry"
  (`C:\Users\jazzo\Downloads\poc-project-man.pdf`). The HTML prototype and the Folio mock-up from
  that conversation were not saved.

## State (v1 done)

- All 19 steps of PLAN.md are done, plus "link a branch by hand" and the `make nvim` fix: 23
  commits, one per feature or fix.
- `make test` / `flutter test`: 41 tests pass. Unit tests cover the parsers, edits, archive,
  inbox, branch links, PR and Changes state; integration tests run a headless Neovim with the
  plugin (`test/support/nvim.dart`). `flutter analyze` is clean.
- About 8000 lines of Dart including tests. The only dependency is Flutter itself: no state
  framework, no msgpack package, no YAML or Markdown package.
- **Verified by screenshots** on a scratch clone of nvimos-meta: every Tasks screen, Review with
  the Verify panel (a ticked checkbox reached the file), archive, spec browser, legacy, milestones.
- **New change ran with a real agent:** `claude -p` drafted
  `openspec/changes/97-oil-preview-wrap-and-render` with proposal, tasks, an `oil` delta, TASK-97
  and its `index.tsv` row, and the app opened the change.
- **Run on the real setup** (2026-11-10): the user's nvim-qt with their full config, in
  `~/es/nvimos-meta`, with the release build. It showed 96 tasks, 62 changes and 115 legacy notes.
  The PR view is empty there because that repo has only `main`.

## Decisions

| Topic         | Choice                                                                        |
|---------------|-------------------------------------------------------------------------------|
| Platform      | native Windows; Flutter 3.47.9 / Dart 3.13.7 in `H:\flutter` (exFAT drive), `PUB_CACHE=H:\pub-cache`, VS2022 C++ tools. WSL's Flutter is not used |
| Connection    | TCP 127.0.0.1:6666 (Dart can't open Neovim's named pipes); address from `args[0]` or `NVIMOS_ADDR`, else the connect screen; retries every 2 s |
| Git and files | only through the backend (`git.*`, `files.*`, `jobs.*`)                       |
| Editing prose | only in Neovim; the app edits status, priority, checkboxes, and creates task files |
| Click in PR   | `show(head, path, line)`: read-only buffer of the branch's version (question 3 still open: or check the branch out) |
| Click in Changes | `open(path, line)`: the working-tree file                                  |
| State         | plain `ChangeNotifier`s and `ValueNotifier`s; `SessionScope` (InheritedNotifier) |
| msgpack       | own codec (`rpc/msgpack.dart`), ext types decoded (Neovim handles)            |
| Branch ↔ task | automatic when the branch name or its commits name `TASK-<n>` or the change id; or linked by hand. Hand links live in `%APPDATA%\nvimos\state.json`, not in task files, because the Backlog.md CLI may drop unknown YAML fields |
| Last seen     | per repo in the same `state.json`; the inbox shows what changed since then    |
| Writes        | optimistic: the UI updates at once, then `files.set_lines` with `expect` lines; on refusal (stale or unsaved buffer) it reloads and shows the error |
| Archive       | `openspec archive` when the CLI is installed; else our own: merge deltas into `openspec/specs/<cap>/spec.md`, mark Done, move to `changes/archive/<date>-<id>/` |
| New change    | `claude -p --permission-mode acceptEdits --allowedTools Read,Write,Edit,Glob,Grep`, prompt on stdin, as a backend job; the app watches the `jobs` events and opens the new change |
| Statuses      | To Do, In Progress, Needs Test, Done, Dropped (from the repo's Backlog config) |

## Architecture

| Path                     | Does                                                                    |
|--------------------------|-------------------------------------------------------------------------|
| `lib/main.dart`          | entry; address from args / env                                           |
| `lib/rpc/`               | msgpack codec; `NvimRpc` (requests, responses, notifications stream); `NvimError.short` for one-line messages |
| `lib/backend/`           | `Backend.connect` (checks protocol v1), `attach`, typed calls, events with seq check → `resync` on a gap; `models.dart` |
| `lib/state/session.dart` | connection with retry; attaches buffers, windows, git, jobs; `gitChanged`, `changedPaths`, `jobs`, `run()` (returns the error text or null) |
| `lib/state/pr.dart`, `changes.dart` | view state of the two git modes; refresh on `gitChanged`; no notify after dispose |
| `lib/state/prefs.dart`   | `state.json`: lastSeen, branchLinks                                       |
| `lib/tasks/`             | pure Dart: `markdown.dart` (blocks, checks), `parse.dart`, `model.dart`, `edits.dart` (line edits), `archive.dart`, `inbox.dart`, `workspace.dart` (loads all planning files through Neovim, actions) |
| `lib/ui/`                | `shell.dart` (rail + IndexedStack of the 3 modes, owns PrState and Workspace), `connect.dart`, `pr_view.dart`, `changes_view.dart`, `diff_view.dart`, `file_tree.dart`, `theme.dart`, `widgets.dart` |
| `lib/ui/tasks/`          | `tasks_view.dart` (sidebar, list, keys, panel), details for task, change, spec, legacy, milestone; `review_panel.dart`; `dialogs.dart` (new task, palette, new change); `rich.dart` (typed rendering of Markdown blocks); `icons.dart` |

Data flow: Neovim event → `Session` → `gitChanged` / `changedPaths` → PrState / Workspace re-query
→ views rebuild. The Workspace reloads only the changed planning files when the hint names them.

## Look and feel

The direction: **Linear's ideas, not its name or assets.** Dense and calm, dark first, one strong
accent, everything clickable, nothing that looks like Markdown.

**Colors** (`lib/ui/theme.dart`, class `C`):

| Token       | Hex       | Use                                   |
|-------------|-----------|---------------------------------------|
| `bg`        | `#0F1117` | window background                     |
| `surface`   | `#16181F` | panes, sidebar                        |
| `surface2`  | `#1C1F28` | inputs, menus, code blocks, tooltips  |
| `hover`     | `#232733` | row hover and selection               |
| `border`    | `#262A36` | dividers, scrollbar thumb             |
| `text`      | `#E6E8EC` | main text                             |
| `muted`     | `#8B90A0` | secondary text, icons                 |
| `faint`     | `#5C6170` | ids, disabled                         |
| `accent`    | `#6C8CFF` | the one accent: links, focus, primary button, active rail item |
| `green` / `red` / `yellow` / `purple` | `#4CC38A` / `#E5484D` / `#E6B450` / `#A78BFA` | added, removed/errors, in progress, needs test |
| `addBg` / `delBg`, `addGutter` / `delGutter` | `#13261C` / `#2A1517`, `#1B3A29` / `#3E1D20` | diff lines and gutters |

**Type** (class `T`): Segoe UI. Title 14 w600, body 13, small 12 muted, tiny 11 muted, section
headers 11 w600 muted with letter spacing .6 (uppercase in the git views: "COMMITS", "FILES
CHANGED"). Code is Consolas 12.5, line height 1.35.

**Layout:**

- **Whole window:**
  - left rail 48 px with three mode icons; the active one has an accent bar;
  - bottom status bar: connection dot and address, current branch, Neovim's current file and
    cursor (live).
- **Pull request:**
  - sidebar 300 px: base/head pickers with a swap button, COMMITS, FILES CHANGED as a tree with
    +/- counts;
  - the unified diff fills the rest;
  - when reviewing a task, a 300 px Verify panel sits on the right and a review banner links back
    to the task.
- **Changes:** sidebar 320 px with staged/unstaged lists and checkboxes; hunks with Stage, Unstage
  and Discard buttons; commit box.
- **Diff:** gutters 44 px per line-number column, add/del backgrounds, hunk headers muted.
- **Tasks:**
  - sidebar 220 px: workspace name with a letter avatar, Inbox, status filters with counts,
    Changes, Specs, Milestones, Legacy notes, then LABELS;
  - main list: header with title, count, filter field (`/`), group-by menu;
  - detail panel slides in from the right (180 ms), 45 % of the remaining width, clamped 360–600
    px.
- **Dialogs:** 560–620 px wide, centered.

**Elements:**

- `HoverRow`: the list item everywhere; it highlights on hover and selection. Rows are tight,
  with the muted id before the title and the meta on the right.
- Status: Linear-style circles (`StatusIcon`):
  - To Do: an empty ring;
  - In Progress: half filled, yellow;
  - Needs Test: a ring with a dot, purple;
  - Done: a check, accent;
  - Dropped: a cross.
- Priority: Linear-style bars (`PriorityIcon`); no priority is three faint dashes.
- `Pill`: small rounded labels for statuses, labels and the Added / Modified / Removed of
  requirement cards.
- Detail panels: a `PanelHeader` (kicker = id, title, actions, close), then `Prop` rows (label
  column 96 px) with menus and link chips, a divider, then `DetailSection`s (Description,
  Acceptance criteria, Verify, Definition of done) with a progress bar on the right.
- Checklists are live: a click writes the file. "Original notes" are collapsed behind
  "show N lines".
- Requirement cards hold their scenarios; deltas never show as +/- lines.
- Every id, path, branch and dependency is a `LinkChip` or link that opens its record, or Neovim
  at the line.
- Empty states are centered muted text ("Pick two different branches.").
- Tooltips appear after 500 ms; small spinners (1.5 px stroke) show loading next to titles.

**Keys in Tasks:**

| Key       | Does                                         |
|-----------|----------------------------------------------|
| J / K     | move down / up; the arrows work too          |
| Enter     | open the selected item                       |
| Esc       | close the panel                              |
| /         | filter                                       |
| C         | new task                                     |
| S / P     | cycle status / priority                      |
| Ctrl+K    | command palette                              |

The mouse stays first-class.

**Inbox** (default Tasks view): "what changed since last seen" first, then "Needs attention"
groups:

- Waiting to be tried;
- Branches with unreviewed commits;
- In progress without a change;
- Stale active changes (7+ days untouched);
- Legacy notes marked untested.

"Mark all seen" resets lastSeen.

## How the work was done

- **Plan first.** PLAN.md listed the decisions and numbered steps; each step was one commit.
  Fixes got their own commits.
- **Verification:**
  - unit tests for every pure piece;
  - integration tests against a real headless Neovim;
  - then screenshots of the release build, driven by small scratch scripts:
    - `shot.ps1 -Out <png>`: PrintWindow, works when the window is covered; moves the window to
      40,40;
    - `click.ps1 -X -Y [-Keys]`: clicks in screenshot coordinates. The first click may only focus
      the window, so click twice;
    - `restart.ps1 -Port -Dir [-Build]`.

    They live in the session scratchpad, not in the repo.
- **Writes were checked on a scratch clone** of nvimos-meta, never on the real repo. A headless
  Neovim ran on 6677/6678/6679 for that.
- **Agents:** the New change flow was tried end to end with a real `claude -p`.

## Style and conventions

- **Dart:**
  - formatted at 120 columns (`analysis_options.yaml`, `dart format -l 120`), `flutter_lints`;
  - short widgets, private `_Widget`s per file, `const` where possible;
  - class names `C` and `T` for colors and text styles.
- **Comments:** one-line `///` doc comments saying what a thing is for; no chatter.
- **Errors:** actions return `String?` (the error text) instead of throwing into the UI; it shows
  in a SnackBar.
- **Makefile:** pwsh recipes, `make help` with sections `run` (nvim, run, build), `test` (test,
  analyze) and `other`. It sets `FLUTTER_ROOT=H:/flutter` and `PUB_CACHE`.
- **Line endings:** `.gitattributes` uses LF, except `*.bat` (CRLF); `*.ico` and `*.png` are
  binary.
- **Commits:**
  - one per feature, one per fix, prefixed by area (`rpc:`, `backend:`, `session:`,
    `pull request view:`, `changes view:`, `tasks:`, `fix`-style subjects for fixes, `plan:`,
    `style:`, `README:`);
  - commit as you go without asking, on `main`, in the main checkout, never push;
  - the Claude co-author line at the end.
- **Docs:** short sentences, tables for references; README for running, PLAN for decisions.

## Lessons and gotchas

- **lazy.nvim resets the runtimepath**, so `make nvim` adds the plugin with `-c` after the config
  (`set rtp^=… | runtime plugin/nvimos.lua`), not `--cmd`. In a Neovim that is already running,
  `:set rtp^=~/es/nvimos-poc-backend | runtime plugin/nvimos.lua`, or `:NvimosServe` once the
  plugin is loaded.
- **Flutter on exFAT** works, but every build prints a harmless `Unblock-File … Zone.Identifier`
  error (exFAT has no alternate data streams). `git config --global --add safe.directory
  H:/flutter` was needed.
- **Don't edit Dart through Python heredocs:** `'\n'` turned into real newlines inside Dart strings.
  Use the Edit tool. Commit from Bash, not from a PowerShell here-string.
- **Notifying after dispose** crashed when a refresh finished after the view was gone; guard with
  a `_disposed` flag.
- **Loading every planning file** took seconds when each read was a git call; the backend fix
  (cached root) brought it back under a second.

## Gaps against the prompts

- **No board view:**
  - the list groups by status, priority or label, but there are no kanban columns;
  - there's no group by milestone;
  - the README says "list and board views", which overstates it.
- **No saved views** like "agent tonight"; the sidebar's status filters are the only views.
- **CLI aggregates not merged:** `openspec view/list/status --json` aren't called on a timer; only
  `openspec archive` is used when present.
- **Change detail has no tabs:** Proposal, Spec, Design and Tasks are stacked sections. "View raw"
  is Open in Neovim.
- **Agent state per task** is only "branch has N commits ahead"; there are no logs.
- **No side-by-side diff or syntax colors** in the diff; no light theme.
- **No window title or icon work:** the title bar still says `nvimos_poc`, with the default
  Flutter icon.
- **Question 3 is still open:** branch review click shows the read-only copy; the alternative is
  checking out.

## Ideas for v2

- A board view (status columns, drag to change status) and saved views.
- A proper app name and icon; window size and position remembered in `state.json`.
- Side-by-side diff with syntax colors (tree-sitter highlights from Neovim).
- Streamed agent output in a job panel, once the backend streams it.
- Light theme from the same tokens.
