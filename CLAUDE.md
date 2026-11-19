# Ops (nvimos-poc-frontend)

Flutter Windows app, GitHub `nvimos/ops`, exe `ops.exe`; `PLAN.md` is the spec.
Backend plugin: relay (`nvimos/relay`), checkout `../nvimos-poc-backend`.
The original idea files (`~/ws/nvimos-meta/poc-nvim-backend/flutter*.md`) hold main ideas only;
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
- The whole suite takes about 2–3 minutes (2026-11-19, 4 files at a time). `workspace_test.dart` "archive merges deltas" is flaky
  (fails about half the runs, also before 2026-11-11); don't chase it as a regression.
- Flutter: `C:/tools/flutter` (Makefile `FLUTTER_ROOT`), `PUB_CACHE=C:/tools/pub-cache`. Use only
  this SDK, also for a quick `pub get`, analyze or test. Never `H:/flutter` (an older checkout):
  running it rewrites `.dart_tool/package_config.json` to its framework, and the next hot reload of
  `make live` (built with `C:`) fails on framework/engine mismatches such as `SemanticsRole` not
  exhaustively matched (2026-11-19). Check `"flutterRoot"` in `package_config.json` if a reload
  breaks oddly; `C:/tools/flutter/bin/flutter pub get` repairs it.
- `make test` runs 4 files at a time (`TEST_CONCURRENCY ?= 4`, 2026-11-19). The Neovim tests
  `pr_state_test` "Down past the last file…" and `status_store_test` ("connection closed") failed
  at 4 and passed one at a time; rerun them with `--concurrency=1` before treating them as regressions.
- `tasks_meta_test` "every OpenSpec change parses and names its task" fails while
  `nvimos-meta/openspec/changes/kanban-board-mode` has no backlog task (open: give it a task or let
  the test allow proposals without one).
- A test that needs another platform uses `variant: TargetPlatformVariant.only(TargetPlatform.windows)`,
  not `debugDefaultTargetPlatformOverride` with `addTearDown`: the tear-down runs after Flutter's
  check that debug variables are reset, so the test fails.
- `make analyze` lists `package:flutter/material.dart` deprecation infos on every file
  (Flutter 3.50); anything else is a real finding.
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
- How this project applies the general rules (_For future Flutter projects_, at the end)
  - derived lists are keyed on the identity of their input: the status store replaces `Status`
    and never edits one (`AddIgnoreState.rows`, `ChangesState.staged`); `TaskBrowser.rows()` has
    no single input, so it is dropped on every notice of the browser or the workspace except a
    cursor or selection move
  - the shell hands the same mode view instances down until their inputs change (`_modeViews`)
  - the rail snaps its width and fades only its labels
  - per-item work stays trivial: `Task.number` once built a `RegExp` per call inside a sort
  - checked with a `UiTiming` span (`<area>.<action>`, `markPainted()` for the frame on screen) and
    a test that a cursor move keeps the derived data (`identical`)

## Keys

- The shell owns app-wide keys (Alt+] / Alt+[ / Alt+1..9, Ctrl+B, `?`) and gives the keyboard
  to the shown mode on every mode switch. A mode with its own keys has a `focus` node; no
  `autofocus` in a mode, or a hidden mode in the IndexedStack takes the keys.
- Plain keys are ignored while a text field has focus (`_typing()` in the shell).
- Two-key commands (`gs`, `]f`, `zw`) go through `KeySequence` (`lib/ui/key_sequence.dart`).
  A one-key command can't be the start of a longer one: a bare `z` never fires while `zw`, `zh`,
  `zR` exist. That's why the view cycle is `Z`.
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
  - `make pdf-on` (`tool/pdf.ps1`) writes the git-ignored `pubspec_overrides.yaml`, which points
    `ops_pdf` at `packages/ops_pdf_on` (pdfrx), and runs `pub get`; `make pdf-off` removes it,
    `make pdf-status` says which one is active
  - PDF is off locally, and `make release` turns it off before it builds (2026-11-19: the PDF
    build is not tested yet, and an untested one was shipped once); build with PDF on now and then
    to check it still compiles
  - while PDF is on, `pubspec.lock` shows as modified; commit the lock from the off state
  - `analysis_options.yaml` excludes `packages/ops_pdf_on` (its pdfrx import only resolves when on)
- `BUILD_CONCURRENCY ?= 4` in the Makefile is exported as `CMAKE_BUILD_PARALLEL_LEVEL` for the
  native build (2026-11-19; not yet checked that `flutter build windows` honours it)
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
- Measure: a stopwatch from the input event to the next painted frame
  (`addPostFrameCallback` after `scheduleFrame`), recorded per interaction, says where the time
  goes. "It waits for a double click" was a rebuild of every page; the measurement tells them apart.
