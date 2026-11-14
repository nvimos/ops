# Ops (nvimos-poc-frontend)

Flutter Windows app, GitHub `nvimos/ops`, exe `ops.exe`; `PLAN.md` is the spec.
Backend plugin: relay (`nvimos/relay`), checkout `../nvimos-poc-backend`.
The original idea files (`~/es/nvimos-meta/poc-nvim-backend/flutter*.md`) hold main ideas only;
the plan wins where they disagree. Keep them vague (no buttons, no keys) when updating them.

## Running tests

- Never wait on a hung test. Every run has a timeout at two levels:
  - per test: `dart_test.yaml` sets `timeout: 11s`, and `make test` passes
    `--timeout $(TEST_TIMEOUT)` (Makefile, 11s; keep the two equal);
    a test that needs longer sets its own `timeout:` explicitly
  - per command: give the shell tool call a timeout of a few minutes, not the 10-minute maximum,
    and run one test file (`flutter test test/<file>.dart`) while iterating.
  - file operations (`cat`, here-docs, `sed`, small scripts that write files) get a shell tool
    timeout of 10 s at most: they never take longer.
- Run only the test files that cover the change or feature (`flutter test test/a_test.dart
  test/b_test.dart`), not the whole suite; analyze (`make analyze`) after every change.
- Widget tests run on a fake clock: no real sockets or `await` on real I/O in the test body (it
  never completes), no `pumpAndSettle` with a repeating animation or timer (spinners, retry
  timers). Use `pump(duration)`. For real Neovim in a widget test, do the I/O inside
  `tester.runAsync` (see `test/tasks_view_test.dart`).
- Tests that need Neovim are plain `test()`s with `TestNvim` (`test/support/nvim.dart`).
- A test cleans up after itself: no fixture, scratch folder or other artifact may be left behind.
  Polluting the temp folder is not acceptable (1,000+ `nvimos_repo_*` folders and 80+ git
  fsmonitor daemons piled up once and slowed the machine).
  - a temp dir a test creates goes through `keepForCleanup(...)` (`test/support/temp_dirs.dart`);
    `test/flutter_test_config.dart` deletes them when the test file is done. `makeRepo()` and
    `TestNvim.start()` already do it.
  - so does everything else a test starts or writes: processes (`TestNvim.start()` registers
    `addTearDown(stop)` itself, so a failing test leaves no nvim), files outside the repo,
    background daemons. Test repos set `core.fsmonitor=false` (the `git()` helper passes it),
    because git's fsmonitor starts a daemon per repo that outlives the test.
  - a new kind of fixture gets its cleanup in the same change, and the test run is checked: the
    count of `nvimos_*` folders in `%TEMP%` is the same before and after.
  - a run that was killed or crashed leaves things behind: remove them (the folders, the headless
    `nvim --clean` processes, the daemons) and don't leave them for the user.
- The whole suite takes about 25 s. `workspace_test.dart` "archive merges deltas" is flaky
  (fails about half the runs, also before 2026-11-11); don't chase it as a regression.
- Flutter: `C:/tools/flutter` (Makefile `FLUTTER_ROOT`), `PUB_CACHE=C:/tools/pub-cache`.
- `make analyze` lists `package:flutter/material.dart` deprecation infos on every file
  (Flutter 3.50); anything else is a real finding.
- New code uses no deprecated APIs (Flutter, Dart, packages): look up the replacement instead. The
  `material.dart` import infos are the one accepted exception, until the move to `material_ui`.

## UI code

- Follow `declarative_ui_guidelines.md`: at most 3 levels of inline layout nesting, `build` under
  50 lines (extract named sub-widgets), lists from data with builders, no logic inside event
  handlers (call a named method or the state object), dumb atoms and molecules that take values
  and emit callbacks.
- A view is a page (State) with named event handlers; the work is in a `ChangeNotifier` under
  `lib/state/` or `lib/tasks/`, which tests can drive without widgets.
- Never look up an InheritedWidget (`SessionScope.read(context)`) in `dispose()`; keep the
  reference from `didChangeDependencies`.
- A label is part of its control: a click on the text next to a button or box does what the button
  or box does (the word beside the sort button, the text of a checkbox). Wire the label into the
  same tap target; the exception is a label that has an action of its own.
- An interactive item shows the pointer cursor (`SystemMouseCursors.click`, the pointing hand) while
  the mouse is over it, so it reads as clickable: buttons, rows that open something, checkboxes,
  their labels, a hidden button like the `+` of a diff block. Always, unless the user says
  otherwise, and set it explicitly on every new clickable (a `MouseRegion` or the widget's
  `mouseCursor`), not by trusting a default; a disabled item keeps the default.
  - exception, by the user: the file rows of the file lists (Changes, Pull request) keep the plain
    cursor, a click on a file is obvious there (`HoverRow(pointer: false)`); folder rows and the
    stage buttons at the end of a row still get the pointer
  - an interactive item also has a tooltip saying what it does
  - inside a `SelectionArea` (the diff, lists) a `Text` brings its own I-beam cursor, which beats an
    outer `MouseRegion`: wrap the button's content in `SelectionContainer.disabled`
  - check the new item for both before saying it is done
- Errors: `Session.run` returns the full error text (with Neovim's trace). Show a failed load
  with `ErrorPane` in place of the view, a failed action with `showActionError` (short snackbar,
  Details opens the selectable trace).

## Performance

- A click changes the state at once (optimistic), then calls the backend; the refresh after it
  keeps the change or puts it back. Don't make a click wait on an RPC to redraw.
- Measure before optimizing: `UiTiming.instance` (`lib/timing/ui_timing.dart`) has `span`,
  `sync`, `time`; give a new state action a span named `<area>.<action>`. Plain tests see the
  samples in `UiTiming.instance.samples` / `summary()`.
- Watch per-item work in loops over hundreds of files: a getter that builds a `RegExp` or
  re-parses (as `Task.number` did) inside a sort costs whole frames.

## Keys

- The shell owns app-wide keys (Alt+] / Alt+[ / Alt+1..5, Ctrl+B, `?`) and gives the keyboard
  to the shown mode on every mode switch. A mode with its own keys has a `focus` node; no
  `autofocus` in a mode, or a hidden mode in the IndexedStack takes the keys.
- Plain keys are ignored while a text field has focus (`_typing()` in the shell).
- Two-key commands (`gs`, `]f`, `zw`) go through `KeySequence` (`lib/ui/key_sequence.dart`).
- Panes and lists: a pane is a part of a mode that takes the keys; a list is a pane that enumerates
  items (files, commits, directories, tasks). Every mode with panes follows the same motion rules:
  - Up / Down and `j` / `k` (arrows, hjkl and WASD are the same keys; a command that wanted one of those
    keys moved, and conflicts are the user's to decide). A handler never binds these letters itself:
    it asks `navKey(event)` (`lib/ui/nav_keys.dart`), so they cannot drift apart (the one exception is
    the key at D's position on QWERTY, matched by scan code: it is Right on the user's layout); a pending key
    sequence (`KeySequence.pending`, the `w` of `zw`) goes first: the previous / next item of the
    active list, in the order the list shows them (file trees: top-level files, then folders)
  - past the last item, one more Down goes to the pane visually below the list, past the first item
    Up goes to the pane visually above it; never to the diff
    (PR: head picker < FILES < COMMITS; Changes: STAGED < CHANGES < commit message)
  - Right / `l` goes from a list to the pane on its right (the diff); Left / `h` comes back to the
    list it came from
  - in a diff, Up / Down scroll 3 lines, Shift (or `J` / `K`) 10; `]c` / `[c` jump hunks
  - Tab / Shift+Tab visit every stop in visual order and wrap round, like a Windows or HTML page;
    the mode rail is one stop in front of the first (not each mode in it); Ctrl+arrow jumps to the
    pane in that direction; Left from a leftmost list goes to the rail
  - going up into a list from a lower pane selects its lowest visible item
  - a list keeps its selected row in view (`lib/ui/reveal.dart`); the active list's title is lit
  - the logic lives in the state class (`movePane`, `moveCursor`), not in the key handler, so a
    test can drive it; the debug bar (bug button, bottom right) shows where the focus is
  - the debug bar names the focused element by its role in the interface, not its class: a new
    `FocusNode` gets a `debugLabel` and an entry in `focusRoles` (`lib/ui/debug_bar.dart`); a
    mode with several panes under one node adds its panes to the pane tables there; it also shows
    the last key and the last mouse button or wheel event
- A new key goes into three places: the handler, `keyTable` in `lib/ui/help_view.dart` (the Help
  mode), and the Keys table in `PLAN.md`.

## Git and files

- Commit per feature, message `area: what changed`, the body says why; end with the
  Co-Authored-By line.
- The backend repo often has the user's uncommitted work: add only your own paths, never `-a`.
- A worktree starts from the local `main`, not `origin/main`: local main has commits that are not
  pushed yet, and a worktree made from the remote would lack them. Create it from local HEAD
  (`git worktree add -b <branch> <path> main`), or set the worktree tool's base to `head`
  (`worktree.baseRef`), not the default `fresh`.
- Edit files with the Edit tool, several calls in one response when a change spans places: no script
  to write, no interpreter to start. A script (Python with `newline=''`, `sed`) only for a mechanical
  change over many files or many identical spots, where one command beats many edits. Not a habit,
  not a way around a failing shell heredoc (use Write or Edit then).
- Don't show diffs or code in the chat unless asked: this app is the review tool, the changes are read
  there. Replies are a short summary of what changed and where (file names, behavior), not hunks,
  `git diff` output or pasted code. Run `git diff` for yourself only when you need it, and don't
  quote it back.
  - The diff drawn under an Edit call is Claude Code's own display; CLAUDE.md cannot hide it, and no
    documented setting collapses it to a one-liner. Closest, unverified: `viewMode` (`focus`) in
    `~/.claude/settings.json`, `Ctrl+O` toggles the detailed transcript, `/diff` opens a diff panel.
- Python on Windows writes CRLF in text mode: open files with `newline=''` to keep LF.
- `PLAN.md` uses fold markers in HTML comments (`<!-- {{{ -->`) and list items as a topic line
  with one point per line underneath. Sections marked _not strictly normative_ describe what is,
  not what must be.

## Build notes

Moved from `PLAN.md`, which describes what the app does, not how it is built.

- `make live` logs
  - everything flutter and the app print is also written to `out/live.log` (a new file per run)
  - `out/` is ignored by git
  - read its last lines when diagnosing what the running app did
- `make timings` shows the UI timings (`WHICH=totals` or `<n>` sessions back, `FILTER=tasks`);
  `make measure` prints the timings of Tasks clicks in a 300-task repo
- new backlog tasks (`nvimos-meta/backlog/tasks`)
  - before taking a number, look at what other worktrees are doing: `git worktree list` in
    `nvimos-meta` and in the frontend, the tasks folder of each, the other branches
    (`git ls-tree -r --name-only <branch> -- backlog/tasks`), and uncommitted or untracked task files
    in the main checkout
  - take the next number above the highest found anywhere, so a task made here doesn't clobber one
    a worktree is adding
  - a worktree that adds tasks reads the main checkout's numbers the same way
  - the number is in the id, the file name (`task-<n> - <slug>.md`) and the `ordinal` (`<n>000`)
- Flutter on exFAT (`H:`): if builds fail on symlinks or file locks, move the SDK to an NTFS drive.

### Build order (one commit each)

1. `flutter create --platforms=windows`, app shell with the sidebar and an empty main area.
2. RPC client with tests against a headless `nvim --listen`.
3. Backend wrapper: attach, events, seq checks, resync.
4. Connection screen: address field, connect, retry, status bar with the live cursor.
5. Pull request view: branch pickers, commit list, file tree.
6. Unified diff view.
7. Click to show in Neovim (`show` / `open`).
8. Live refresh from git hints and buffer events.
9. Changes view: file stage/unstage/discard.
10. Hunk stage/unstage/discard.
11. Commit.
12. Tasks: parsers with unit tests.
13. Tasks: repo loading and the list + detail panel (read-only), Linear-style shell.
14. Tasks: status, priority and checkbox edits; keyboard.
15. Tasks: inbox with "Needs attention".
16. Tasks: branch link and Review tie-in with the Pull request view.
17. Tasks: archive into spec, spec browser with "changes that touched this".
18. Tasks: legacy viewer with Promote to task; milestones.
19. README: how to run (`nvim --listen 127.0.0.1:6666`, `flutter run -d windows`).
