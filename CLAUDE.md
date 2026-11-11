# nvimos-poc-frontend

Flutter Windows app; `PLAN.md` is the spec. Backend plugin: `../nvimos-poc-backend`.

## Running tests

- Never wait on a hung test. Every run has a timeout at two levels:
  - per test: `dart_test.yaml` sets `timeout: 45s`, and `make test` passes `--timeout 45s`;
    a test that needs longer sets its own `timeout:` explicitly
  - per command: give the shell tool call a timeout of a few minutes, not the 10-minute maximum,
    and run one test file (`flutter test test/<file>.dart`) while iterating.
- Widget tests run on a fake clock: no real sockets, no Neovim, no `pumpAndSettle` with a
  repeating animation or timer (spinners, retry timers). Use `pump(duration)` instead.
  Tests that need Neovim are plain `test()`s with `TestNvim` (`test/support/nvim.dart`).
- Flutter: `C:/tools/flutter` (Makefile `FLUTTER_ROOT`), `PUB_CACHE=C:/tools/pub-cache`.
- `make analyze` lists `package:flutter/material.dart` deprecation infos on every file
  (Flutter 3.50); anything else is a real finding.

## UI code

Follow `declarative_ui_guidelines.md`: at most 3 levels of inline layout nesting, `build` under
50 lines (extract named sub-widgets), lists from data with builders, no logic inside event
handlers (call a named method or the state object), dumb atoms and molecules that take values
and emit callbacks.
