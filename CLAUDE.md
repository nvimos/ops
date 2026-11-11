# nvimos-poc-frontend

Flutter Windows app; `PLAN.md` is the spec. Backend plugin: `../nvimos-poc-backend`.
The original idea files (`~/es/nvimos-meta/poc-nvim-backend/flutter*.md`) hold main ideas only;
the plan wins where they disagree. Keep them vague (no buttons, no keys) when updating them.

## Running tests

- Never wait on a hung test. Every run has a timeout at two levels:
  - per test: `dart_test.yaml` sets `timeout: 45s`, and `make test` passes `--timeout 45s`;
    a test that needs longer sets its own `timeout:` explicitly
  - per command: give the shell tool call a timeout of a few minutes, not the 10-minute maximum,
    and run one test file (`flutter test test/<file>.dart`) while iterating.
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

## UI code

- Follow `declarative_ui_guidelines.md`: at most 3 levels of inline layout nesting, `build` under
  50 lines (extract named sub-widgets), lists from data with builders, no logic inside event
  handlers (call a named method or the state object), dumb atoms and molecules that take values
  and emit callbacks.
- A view is a page (State) with named event handlers; the work is in a `ChangeNotifier` under
  `lib/state/` or `lib/tasks/`, which tests can drive without widgets.
- Never look up an InheritedWidget (`SessionScope.read(context)`) in `dispose()`; keep the
  reference from `didChangeDependencies`.
- Errors: `Session.run` returns the full error text (with Neovim's trace). Show a failed load
  with `ErrorPane` in place of the view, a failed action with `showActionError` (short snackbar,
  Details opens the selectable trace).

## Keys

- The shell owns app-wide keys (Alt+] / Alt+[ / Alt+1..5, Ctrl+B, `?`) and gives the keyboard
  to the shown mode on every mode switch. A mode with its own keys has a `focus` node; no
  `autofocus` in a mode, or a hidden mode in the IndexedStack takes the keys.
- Plain keys are ignored while a text field has focus (`_typing()` in the shell).
- Two-key commands (`gs`, `]f`, `zw`) go through `KeySequence` (`lib/ui/key_sequence.dart`).
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
