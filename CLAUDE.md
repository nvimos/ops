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
  their labels. A `MouseRegion` or the widget's `mouseCursor`; a disabled item keeps the default.
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
- Python on Windows writes CRLF in text mode: open files with `newline=''` to keep LF.
- `PLAN.md` uses fold markers in HTML comments (`<!-- {{{ -->`) and list items as a topic line
  with one point per line underneath. Sections marked _not strictly normative_ describe what is,
  not what must be.
