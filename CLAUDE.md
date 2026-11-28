# Ops (nvimos-poc-frontend)

Flutter Windows app, GitHub `nvimos/ops`, exe `ops.exe`; `PLAN.md` is the spec.
Backend plugin: relay (`nvimos/relay`), checkout `../nvimos-relay` (git calls in `lua/nvimos/git.lua`).
`../nvimos-poc-backend` is gone, but `make live` still puts it on the rtp (Makefile line 28).
The original idea files (`~/ws/nvimos-meta/poc-nvim-backend/flutter*.md`) hold main ideas only;
the plan wins where they disagree. Keep them vague (no buttons, no keys) when updating them.

## Working with the user

- Several pieces of work at once go to forks in the background, each in its own worktree (Git and
  files), so the main thread stays free for the user's input; the main thread merges, answers and
  asks. Report a fork's result in a few lines when it comes back.
- When a batch of work is done and the user asked for it, ask whether to continue with the
  audible wizard (skill `audible-wizard`): one question, `Continue` / `Stop here` (+ `Read
  again`), and a second one with concrete next steps only when there are some to offer.
- A question the user picks "clarify" on: explain each option in plain words, then ask again.
- Explain a decision through user scenarios (what I do, what I see, what lands in which file) when
  the user doesn't follow a question.

## Running tests

- Never wait on a hung test. Every run has a timeout at two levels:
  - per test: `dart_test.yaml` sets `timeout: 11s`, and `make test` passes
    `--timeout $(test_timeout)` (Makefile, 11s; keep the two equal);
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
- The whole suite takes about 7-8 minutes (2026-11-20, 2 files at a time). `workspace_test.dart` "archive merges deltas" and `status_store_test` "two mode states…" are flaky (also before 2026-11-20); don't chase them as regressions.
- Flutter: `C:/tools/flutter` (Makefile `flutter_root`; Makefile variables are lowercase, 2026-11-23, except the exported
  `PUB_CACHE` and `CMAKE_BUILD_PARALLEL_LEVEL`), `PUB_CACHE=C:/tools/pub-cache`. Use only
  this SDK, also for a quick `pub get`, analyze or test. Never `H:/flutter` (an older checkout):
  running it rewrites `.dart_tool/package_config.json` to its framework, and the next hot reload of
  `make live` (built with `C:`) fails on framework/engine mismatches such as `SemanticsRole` not
  exhaustively matched (2026-11-19). Check `"flutterRoot"` in `package_config.json` if a reload
  breaks oddly; `C:/tools/flutter/bin/flutter pub get` repairs it.
- `make test` runs 2 files at a time (`test_concurrency ?= 2`, 2026-11-20; `dart_test.yaml` says
  the same). The Neovim tests `pr_state_test` "Down past the last file…" and `status_store_test`
  ("two mode states…") failed at 4 and passed one at a time; rerun them with `--concurrency=1`
  before treating them as regressions.
- A test that needs another platform uses `variant: TargetPlatformVariant.only(TargetPlatform.windows)`,
  not `debugDefaultTargetPlatformOverride` with `addTearDown`: the tear-down runs after Flutter's
  check that debug variables are reset, so the test fails.
- `tasks_meta_test` "every OpenSpec change parses and names its task" fails on main (2026-11-28, the
  same with the day's changes stashed); it reads the real `nvimos-meta`, not a fixture. Not a
  regression of a Tasks change.
- The user's settings: `Prefs.load()` reads and writes `%APPDATA%/nvimos/state.json` (last seen per
  repo, branch links). A test that shows `TasksView` or touches `Prefs` sets `Prefs.baseOverride` to
  a `keepForCleanup` temp folder; an ad hoc run on a real repo sets `$env:APPDATA` to a temp folder
  (deleted after), so the user's file is never written.
- Measuring a Tasks interaction in a widget test
  - a tap on a sidebar entry leaves the keys in the sidebar: `j` then moves the sidebar, not the
    list. Press Right first; check `browser.view` / `selected` before trusting a number (a "26 ms
    per move" on 2026-11-28 was sidebar moves)
  - the view's build runs inside a `LayoutBuilder`, so a phase split (buildScope / flushLayout)
    shows build ~0 and all the cost as layout; profile instead (_For future Flutter projects_)
  - a synthetic repo hides per-item costs that real content shows: measure on the snappy fixture
- `make analyze` lists `package:flutter/material.dart` deprecation infos on every file
  (Flutter 3.50); anything else is a real finding. Also accepted: the info in
  `test/browser_labels_test.dart:12` (prefer_function_declarations_over_variables), old.
- New code uses no deprecated APIs (Flutter, Dart, packages): look up the replacement instead. The
  `material.dart` import infos are the one accepted exception, until the move to `material_ui`.

## UI code

- Use the typical Flutter names and classes for the elements you create or change (layout, widgets,
  focus, input, and other components): `FocusNode`, `FocusScopeNode`, `Focus`, `Shortcuts`, `Actions`,
  `OverlayPortal`, `RawAutocomplete` and so on. Pick the existing Flutter element that fits the job
  before writing a custom one, and name the custom parts after the Flutter role they play.
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
- Mode rail: one plain icon per mode, nothing under it (sub entries made the rail move when they
  expanded; 2026-11-19). The diff views of Pull request and Changes are the view bar
  (`lib/ui/view_bar.dart`) above all their panes: Unified, Split (side by side), Merge. Merge is
  dimmed unless a merge with conflicts is open; the button stays so the bar doesn't change shape.
- Path rows of the ported Purrage modes (Add and Ignore, Repos) follow Purrage's `PLAN.md`: two
  columns, the folder right-aligned in muted monospace with its trailing slash (`PathFolder`,
  `Expanded(flex: 2)`), the base name left-aligned (`PathName`, `Expanded(flex: 3)`), so the names
  line up (`lib/ui/path_cells.dart`). Directory names take Windows Explorer's folder amber
  (`C.folder`). Tests find a path by its base name, not the whole path.
- Hover is input-modality-aware (`lib/ui/input_modality.dart`): a key press hides every hover look,
  and the hover-only controls inside a row, until the mouse moves or a button goes down, so keyboard
  scrolling never lights up the row that slid under a resting mouse. A new hover effect reads the flag
  the way `HoverRow` does; don't drive hover from `MouseRegion.onEnter` alone.
- The ported Purrage modes carry no hover-only row buttons. Add and Ignore keeps its buttons always
  visible (`+`/`−`, the eye for an untracked row); delete and every other row action live in the row's
  right-click menu (`showMenu`), as in Purrage.
  - exception, by the user (2026-11-19): the lines of the Ignore panes keep their hover buttons
    (Dirname, delete) and also get a right-click menu (OpenSpec change `ops-ignore-pane`)
- The shell keeps every mode built in an `IndexedStack`, each wrapped in
  `ExcludeSemantics(excluding: <not shown>)`. Hidden modes that refreshed sent semantics updates the
  Windows accessibility bridge rejected (`Failed to update ui::AXTree, error: 144 will not be in the
  tree and is not the new root`, hundreds per run). Fix added 2026-11-19, not yet confirmed by a
  mode-switching run.
- The same error from a shown tooltip has another cause (2026-11-20, OpenSpec change
  `ops-tooltip-semantics`). A tooltip's bubble lives in the root overlay; Flutter grafts its
  semantics node under the tooltip's owner (`OverlayPortal`, `traversalParentIdentifier`). When two
  overlay portals (two tooltips in one tappable row, a tooltip and a menu) merge into one semantics
  node, only the first identifier survives (`SemanticsConfiguration.absorb`). The other bubble has
  no parent and is still sent, on every frame of its fade.
  - the id in the message is the next free one, not a place; it is gone from the tree by the time
    you dump it
  - fix: give the tooltip its own node, `Semantics(container: true)` around it
  - the same orphan comes from a mode switch while a tooltip shows: the bubble is outside the
    mode's `ExcludeSemantics` and the offstage `IndexedStack` child, the owner's node goes and the
    bubble stays (`Tooltip.dismissAllToolTips()` on the switch clears it in the same frame), and
    from an open `RawAutocomplete` list under a field wrapped in a `Tooltip`
  - a view test calls `expectTooltipsInSemantics(t)` (`test/support/tooltip_semantics.dart`): it
    shows every tooltip and fails on an orphan overlay node
  - a bubble node has no label (the message is the owner's `tooltip` property): find orphans by
    `traversalChildIdentifier`, not by text
- Buttons inside a text field (`suffixIcon`, `prefixIcon`) that come and go with the text (a clear
  X) go inside `Semantics(container: true)`, as `ClearButton` and the commit field's buttons do.
  Otherwise the first letter gives the field a new semantics node; on Windows with accessibility
  active the bridge then sends the old node "lost accessibility focus", and the field unfocuses:
  typing keeps one letter (2026-11-23, OpenSpec change `ops-commit-field-focus`, Flutter #197193).
  - a new field like that gets a test with `expectStableFocusWhileTyping`
    (`test/support/semantics_focus.dart`), running as Windows
    (`TargetPlatformVariant.only(TargetPlatform.windows)`)
- Errors: `Session.run` returns the full error text (with Neovim's trace). Show a failed load
  with `ErrorPane` in place of the view, a failed action with `showActionError` (short snackbar,
  Details opens the selectable trace).

## Performance

- A click changes the state at once (optimistic), then calls the backend; the refresh after it
  keeps the change or puts it back. Don't make a click wait on an RPC to redraw.
- Measure before optimizing: `UiTiming.instance` (`lib/timing/ui_timing.dart`) has `span`,
  `sync`, `time`; give a new state action a span named `<area>.<action>`. Plain tests see the
  samples in `UiTiming.instance.samples` / `summary()`.
- Proportional work: an interaction costs in proportion to what it changes on screen, not to the
  size of the app or the data. Moving a cursor moves a highlight: it does not rebuild lists, re-sort
  files, rebuild hidden modes or lay out the window. Before adding a `setState`, a
  `notifyListeners`, an animation or a derived getter, ask what it sets off downstream and keep that
  cascade to the part that changed. Four bugs of one kind (2026-11-19), all felt as lag:
  - rail width animation: an `AnimatedContainer` beside the mode area relaid every mode in the
    `IndexedStack` (hidden ones too) on every frame of the slide
  - mode switch: the shell's `setState` made new instances of all nine views, so each one rebuilt
    its whole subtree on a rail click (a few hundred ms in debug, felt like a double-click wait)
  - Add and Ignore: the `rows` getter rebuilt and sorted every file on each read, about a dozen
    reads per arrow key
  - Changes and Tasks: the same per read (`staged` / `unstaged`, `rows()`), several times per key
  - Add and Ignore pane edge: each drag event was a `setState` on the whole view, rebuilding the
    list and the preview; now only `SidePane` listens to the width (`ValueNotifier`)
- Tasks list moves, 2026-11-28 (150-380 ms per `j` on `nvimos-meta` in a widget test, felt as a
  delay); three causes stacked:
  - per-read parsing: `Task.labels` / `acceptance` / `verify` and `Change.taskId` / `status` /
    `stage` re-parsed front matter and proposals (with a `RegExp` built per call) on every read,
    and `inbox()`, the label counts, `changeFor` and `branchFor` read them for every task per
    build. The sidebar's Inbox count alone was 15 ms
  - the whole view under one listener: a selection notified the browser, so the sidebar, the
    header and every row rebuilt (about 4,400 elements) to move one highlight
  - the detail panel keyed by the task's path: every move threw it away and built 950-1,180
    elements anew
- How this project applies the general rules (_For future Flutter projects_, at the end)
  - model objects are replaced, never edited (the workspace makes a new `Task` / `Change` per
    parse), so what is parsed out of one is a `late final` field, computed once; a new derived
    field on them follows suit
  - derived lists are keyed on the identity of their input: the status store replaces `Status`
    and never edits one (`AddIgnoreState.rows`, `ChangesState.staged`); `TaskBrowser.rows()` and
    the sidebar's entries and counts (`_navCached`) have no single input, so they are dropped on
    every notice of the browser or the workspace
  - a selection is not a browser notice: `TaskBrowser.selection` is its own `ValueNotifier`; the
    rows' highlight listens to it per row (`ValueListenableBuilder`, the row content as `child`),
    the list is handed to the selection's builder as a ready `child`, and only the detail panel
    is built again
  - the detail panel has no key: the next task updates it in place, its sections are keyed by
    title, and the view scrolls it back to the top on a new selection
  - the shell hands the same mode view instances down until their inputs change (`_modeViews`)
  - the rail snaps its width and fades only its labels
  - per-item work stays trivial: `Task.number` once built a `RegExp` per call inside a sort
  - checked with a `UiTiming` span (`<area>.<action>`, `markPainted()` for the frame on screen) and
    a test that a cursor move keeps the derived data (`identical`); for the Tasks mode the snappy
    checks (Build notes) hold all of it per view

## Keys

- The shell owns app-wide keys (Alt+] / Alt+[ / Alt+1..9, Ctrl+B, `?`) and gives the keyboard
  to the shown mode on every mode switch. A mode with its own keys has a `focus` node; no
  `autofocus` in a mode, or a hidden mode in the IndexedStack takes the keys.
- Plain keys are ignored while a text field has focus (`_typing()` in the shell).
- Two-key commands (`gs`, `]f`, `zw`) go through `KeySequence` (`lib/ui/key_sequence.dart`).
  A one-key command can't be the start of a longer one: a bare `z` never fires while `zw`, `zh`,
  `zR` exist. That's why the view cycle is `Z`.
- A jump that replaces what is shown (a task link, a review, a mode switch) records where it came
  from first: `NavScope.maybeOf(context)?.push(NavPlace(label, restore))`
  (`lib/ui/nav_history.dart`). The mouse's back button pops it in the shell. A restore must not
  record again (`record: false`), or back would ping-pong.
- The rail's saved order and hidden set are mode **names**, not ids: drop names that are not in
  `Mode.values`, append modes added since the save, dedupe, and never leave `visible` empty
  (`RailState._repair`). A renamed mode starts at the end; a removed one disappears.
- Diff views (Pull request, Changes): `v` toggles Unified and Split, `Z` steps Unified → Split →
  Merge (Merge only while a merge has conflicts; `DiffPrefs.cycleLayout`).
- `Attempted to send a key down event when no keys are in keysPressed` (Alt Left, `repeat: true`)
  right after a hot restart is not an app bug. The restart clears the framework's pressed keys
  while Windows still has Alt down, so the next repeat trips a debug-only assertion in Flutter's
  raw keyboard. Leave it.
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
- Never run `dart format` on a whole file: the code is hand-wrapped, not formatter-clean
  (`page_width: 120` notwithstanding), and one run on `pr_view.dart` reflowed ~100 untouched lines
  (2026-11-28). Write new code in the file's style by hand. Undoing such churn with
  `git checkout -- <file>` is blocked as destructive: ask the user first.
- Parallel work in forks (the user asks for threads so the main thread stays free): one worktree
  per fork beside the repo, `git worktree add -b PR-<slug> ../nvimos-ops-<slug> main`, one commit,
  no merge. Its `pub get` touches `pubspec.lock`, `windows/flutter/generated_plugin*` and adds
  `.flutter_tool_state`: never commit those from a worktree. After the merge, remove it with
  `git worktree remove --force` (only that noise is lost) and `git branch -d` the PR branch.
  Two forks that touch the same file (a test one deletes, another edits) give a modify/delete
  conflict at the merge: carry the edits into the surviving file.
- Tags: lightweight, `v<yyyy-mm-dd>`, with `-HHMM` when asked for a timestamp
  (`v2026-11-28-0414`); local only unless asked to push.
- A new git query goes into both backends: `RepoBackend` (`lib/backend/repo_backend.dart`),
  `NvimBackend` calling the relay's Lua (`nvimos.git.<fn>` in `../nvimos-relay`, committed there
  on its own) and `LocalBackend` running git itself. An older relay lacks a new function: the
  caller catches and degrades (`PrState.merged` shows nothing struck through).
- `PLAN.md` uses fold markers in HTML comments (`<!-- {{{ -->`) and list items as a topic line
  with one point per line underneath. Sections marked _not strictly normative_ describe what is,
  not what must be.

## Build notes

Moved from `PLAN.md`, which describes what the app does, not how it is built.

- `make live` logs
  - everything flutter and the app print is also written to `out/live.log` (a new file per run)
  - `out/` is ignored by git
  - read its last lines when diagnosing what the running app did
  - it also has the running app's VM service URL. Read-only extensions answer over plain HTTP, e.g.
    `curl "<url>/getVM"` for the isolate id, then
    `curl "<url>/ext.flutter.debugDumpSemanticsTreeInTraversalOrder?isolateId=isolates/<n>"`
    (the semantics tree, used 2026-11-19 to find which node the accessibility errors named)
- PDF pages in the preview are an optional build (2026-11-19). pdfrx builds PDFium natively and made
  every build slow. A Dart define can't drop a pubspec dependency, so the switch is a package swap:
  - `pubspec.yaml` depends on `ops_pdf` from `packages/ops_pdf_off` (a stub: a PDF shows its facts,
    the Open button and "PDF pages are not in this build")
  - `make configure pdf=on` (`tool/configure.ps1`, 2026-11-23) writes the git-ignored
    `pubspec_overrides.yaml`, which points `ops_pdf` at `packages/ops_pdf_on` (pdfrx), and runs
    `pub get`; `pdf=off` takes the override out, `make configure` alone prints the options
  - every build option works this way: a package in an `_on` and an `_off` variant, `pubspec.yaml`
    on the default one, a line in the option table of `tool/configure.ps1`; the overrides file is
    the configuration, there is no other state
  - which builds have what (the user's rule, 2026-11-28): everyday builds and tests run fast, and
    PDF doesn't need testing all the time
    - every build and test has PDF off: `dev`, `live`, `run`, `build`, `dist`, `test`, `snappy`,
      `snappy-app`, the test workflows; Markdown and HTML keep their default (on)
    - the exceptions have every option on (PDF, Markdown, HTML): `make single`, `make release`
      (`release_config`) and the release workflow (`.github/workflows/release.yml`, a configure
      step before its `flutter build`)
    - `single` and `release` switch back to `everyday_config` (PDF off) when they are done; a run
      that failed halfway leaves PDF on: `make configure pdf=off`
    - a new build option goes into `release_config`, the workflow's configure step and the table of
      `tool/configure.ps1`
  - the checkout stays on PDF off; don't switch it on for a build or a test run
  - `pubspec.yaml` points at the off stub (a fresh clone builds without PDFium)
  - while PDF is on, `pubspec.lock` shows as modified; commit the lock from the off state
  - `analysis_options.yaml` excludes `packages/ops_pdf_on` (its pdfrx import only resolves when on)
- `build_concurrency ?= 4` in the Makefile is exported as `CMAKE_BUILD_PARALLEL_LEVEL` for the
  native build (2026-11-19; not yet checked that `flutter build windows` honours it)
- `make timings` shows the UI timings (`which=totals` or `<n>` sessions back, `filter=tasks`);
  `make measure` prints the timings of Tasks clicks in a 300-task repo
- snappy checks (OpenSpec change `ops-snappy-ui-checks`), two levels on the same snapshot
  (`test/fixtures/tasks_snappy.json`, `make snapshot from=<repo>`)
  - the snapshot, as the user wants it: plain pretty-printed JSON (not gzip: git compresses and
    deltas text itself, and a refresh stays reviewable), each file's text as a list of lines, its
    mtime, the branch list; the structure verbatim (front matter, headings, checkboxes, `Status:`
    / `Milestone:` lines, fences, tables), prose lines cut to ~40 chars, the 3 longest tasks and
    2 longest proposals kept whole (`"full": true`); only what the Tasks mode reads (no
    `backlog/docs`, no `legacy/`, no unparsed notes in a change folder); about 580 KB
  - `make snappy` (also in `make test`): the widget test; widget counts and "a move rebuilds no
    sidebar" are the gate, the debug times are only printed (10x the limit fails)
  - `make snappy-app` (2026-11-28): the profile app on Windows (`flutter drive --profile`,
    `integration_test/snappy_app_test.dart`, local mode, APPDATA in a temp folder), the engine's
    frame timings per `<view>/<interaction>`; a window opens for a few minutes
  - it records every run in `out/snappy-app/<yyyy-mm-dd-HHMM>.json` and one line per key in
    `out/snappy-app/history.tsv` (the trend), and compares with `test/fixtures/snappy_app_baseline.json`:
    p90 build or raster over 16.7 ms fails, over 1.5x the baseline is drift (`strict=1` fails on it),
    judged only above 4 ms build / 8 ms raster (raster varied up to 2x between two runs with no
    code change, build within about 0.3 ms)
  - `make snappy-baseline` takes the slowest of the last 3 runs per key as the baseline; take it on
    purpose (after a speed-up, on a new machine) and commit it by hand
  - in a profile build keys have no debug names: `sendKeyEvent` needs the `physicalKey`
- new backlog tasks (`nvimos-meta/backlog/tasks`)
  - before taking a number, look at what other worktrees are doing: `git worktree list` in
    `nvimos-meta` and in the frontend, the tasks folder of each, the other branches
    (`git ls-tree -r --name-only <branch> -- backlog/tasks`), and uncommitted or untracked task files
    in the main checkout
  - take the next number above the highest found anywhere, so a task made here doesn't clobber one
    a worktree is adding
  - a worktree that adds tasks reads the main checkout's numbers the same way
  - the number is in the id, the file name (`task-<n> - <slug>.md`) and the `ordinal` (`<n>000`)
  - hands-on checks go in a plain `## Verify` section ("Hands-on checks, kept apart from the build
    steps." then `- [ ]` lines), no marker comments; a feature built but not tried by the user is
    `Needs Test`, `Done` once the user says it works
- milestones are Backlog.md's own milestone files (its docs say to use its CLI; the format was read
  from its source, 2026-11-28; its `milestones:` list in `config.yml` is deprecated). Ops reads and
  creates them; the root `milestones.md` is no longer read
  - `backlog/milestones/m-<N> - <title>.md`; completed = moved to `backlog/archive/milestones/`;
    `N` is one above the highest in both folders, from `m-0`; the title in the file name is
    lowercased, whitespace to `-`, `<>:"/\|?*` removed, at most 50 chars
  - front matter `id: m-0`, `title: "..."`, `due_date: "yyyy-mm-dd"` (only when set), then
    `## Description`
  - a task stores both: `milestone: <title>` (Backlog.md's key; whether Backlog.md itself writes
    the id or the title there is not documented) and `milestone_id: m-<N>` (an Ops key Backlog.md
    doesn't know and its CLI may drop); the id wins when they disagree, the next Ops edit writes
    the current title; reading never rewrites a file
  - a proposal without a task: `Milestone: <title>` and `Milestone-Id: m-<N>` under `Status:` (or
    as their own paragraph under the title); a proposal with a task follows the task
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

## For future Flutter projects

Learnings meant to carry over to other Flutter apps; nothing here depends on this project. Each
says the rule, why, and the trap it came from.

### Responsiveness: proportional work

- The principle: an interaction costs in proportion to what it changes on screen, not to the size of
  the app or the data behind it. Moving a cursor moves a highlight; it does not rebuild lists,
  re-sort data, rebuild what is hidden or lay out the window. Lag in a desktop app is almost always
  a cascade: one small change that, through rebuilds, notifiers and getters, makes work
  proportional to everything.
- Before adding a `setState`, a `notifyListeners`, an animation or a derived getter, trace what it
  sets off downstream: which widgets rebuild, what they read, what that recomputes. Keep the
  cascade to the part that changed.
- Know the three trees: widgets are cheap, short-lived descriptions; elements and `State` persist;
  render objects lay out and paint. "Rebuild" means running `build` methods and reconciling, not
  recreating state. It is CPU on the UI thread, several times dearer in debug builds.
- Widgets compare by identity: a new instance at the same place counts as changed, even with the
  same fields, and Flutter rebuilds its whole subtree. The identical instance (cached or `const`) is
  skipped at once.
  - so a parent's `setState` should not hand fresh instances to expensive children; keep them
    while their inputs are the same, and let each subtree rebuild from its own listeners
  - watch for this above `IndexedStack`, tab views and anything that keeps hidden pages alive: they
    rebuild and lay out what nobody sees
- Derived data is computed once per change of its inputs, not once per read.
  - a getter that filters or sorts looks cheap at the call site and gets read many times per frame
    (the handler, the build, scroll-into-view, side panes); cache it
  - key the cache on the identity of an immutable input (a store that replaces its snapshot object
    instead of editing it makes this trivial and safe); without one, drop the cache on every notice
    that can change it, and let a notice that only moves the cursor or selection keep it
  - a test pins it: after a cursor move the derived list is `identical` to the one before
- Notifiers: a cursor move and a data change are different notices. Listeners that recompute data
  should not run on cursor moves; separate the notifiers or mark the notice.
- `ListenableBuilder` / `ValueListenableBuilder`: listen to the narrowest listenable, wrap the
  smallest subtree that shows it.
- Animate paint, not layout.
  - an animated size (`AnimatedContainer` width, `AnimatedSize`) relays its neighbours every frame;
    next to a large subtree that is a full layout per frame and the animation crawls
  - snap the size, animate only opacity, colour or a transform, inside a `RepaintBoundary`; a
    sidebar toggle reads as snappy when it is instant
- Per-item work in loops over hundreds of items stays trivial: a `RegExp` built per call, or a
  re-parse inside a sort comparator, costs whole frames.
- Drag to resize (a pane edge, a splitter): the edge stays exactly under the pointer, as if grabbed.
  - anchor the drag: on drag start keep the size and the pointer's global x; on each update set
    size = start size ± (pointer x − start x). Don't add `details.delta` to the size the last
    build showed
  - why: several pointer events arrive between two frames; each one added to the same stale size,
    so all but the last delta of a frame were lost and the edge trailed the mouse like a lever
    (Add and Ignore's side pane, 2026-11-19, `lib/ui/side_pane.dart`)
  - start the drag at pointer down (`dragStartBehavior: DragStartBehavior.down`) so the slop is
    not swallowed; clamp only what is shown, not the anchor, so the edge picks the pointer up again
    after it went past a limit
  - the size goes through a narrow listenable (`ValueNotifier`) that only the pane listens to; the
    neighbours are relaid, never rebuilt
  - a test sends several moves without a pump between them and expects the size to change by
    exactly their sum
- A window resize changes a dimension, not the content: cache the content by what it actually
  depends on (a column count, a search query, a list of rows) and hand Flutter the same widget
  instances, so a width change is layout only.
  - Help rebuilt every key column, table and highlighted span on each width change (80-220 ms per
    frame in a widget test). The split and columns are cached by column count and query; a single
    width change reflows at once, a drag (a second change within 150 ms) freezes the table once
    with one-line rows, scales it uniformly per frame, and reflows 150 ms after the last width
    change (`lib/ui/help_view.dart`, 2026-11-20)
  - not laying out hidden modes, tried on 2026-11-20 and reverted (the file is gone): a
    `KeepAliveStack` kept every mode's element and scroll but laid out only the shown child, since
    `IndexedStack` lays out all nine on every window resize. A hidden mode that changed left
    dirty semantics and the log filled with assertions (`!semantics.parentDataDirty`,
    `!childSemantics.renderObject._needsLayout`). Any retry must let a dirty hidden subtree lay
    itself out (or remove it from the render tree) first
  - the Help table keeps at least 250 px per column and clips the right edge below that
- The window is at least 468 px wide (rail 180 + divider + the narrowest pane 280 + its 7 px
  edge), enforced by `WM_GETMINMAXINFO` in `windows/runner/win32_window.cpp`; without it a 280 px
  pane plus the rail overflows.
- Measure: a stopwatch from the input event to the next painted frame
  (`addPostFrameCallback` after `scheduleFrame`), recorded per interaction, says where the time
  goes. "It waits for a double click" was a rebuild of every page; the measurement tells them apart.
- Profile when the stopwatch says "slow" but not why: a CPU profile from inside a widget test.
  - run `flutter test --enable-vmservice <file>`; in the test, `Service.getInfo()`
    (`dart:developer`) gives the VM service URI, `vmServiceConnectUri` (package `vm_service`,
    import `dart:isolate` with a prefix: `Isolate` clashes) connects
  - take `getVMTimelineMicros()` before and after ~30 interactions, then
    `getCpuSamples(isolateId, start, end - start)`; count each function once per sample
    (inclusive) and keep only frames whose `resolvedUrl` is the app's own `lib/`: framework frames
    hide the app's share
  - the app's getters showing up at all (`Task.labels`, `FrontMatter.list`, `inbox`) points at
    per-read work; mostly `Element.mount` / `inflateWidget` points at a subtree remounted per
    interaction (a key that changes, a fresh instance); mostly `updateChild` at a rebuild too wide
  - count what rebuilds with `debugOnRebuildDirtyWidget` (per widget type, one interaction): the
    deterministic check a test can gate on, where times on a busy machine vary 2-3x
  - drop the profiler from the committed test (`vm_service` is only a transitive dependency)
- Model objects that are replaced, never edited, can compute what they derive once (`late final`);
  a getter that parses on every read looks free at the call site and costs a frame once a sidebar
  count or a filter calls it for every item.
- A selection is a narrower notice than a data change: give it its own `ValueNotifier`, let each
  row's highlight listen (the row content as the builder's `child`), and pass the list itself as a
  ready `child` to whatever rebuilds on the selection. A detail panel keyed by its item remounts on
  every move; leave the key off, key its sections, and reset its scroll explicitly.
