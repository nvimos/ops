# Ops

[![ops test](https://github.com/nvimos/ops/actions/workflows/test.yml/badge.svg)](https://github.com/nvimos/ops/actions/workflows/test.yml)

A Flutter Windows app over a running Neovim, for [On-Screen Nvim](https://github.com/nvimos/onscreen). Plan: [PLAN.md](PLAN.md).

Backend: [relay](https://github.com/nvimos/relay), the Neovim plugin (checkout `~/es/nvimos-poc-backend`)
[![relay test](https://github.com/nvimos/relay/actions/workflows/test.yml/badge.svg)](https://github.com/nvimos/relay/actions/workflows/test.yml)

## Run

```
make nvim     # Neovim on 127.0.0.1:6666 with the backend plugin (or :NvimosServe in yours)
make run      # the app; or build/windows/x64/runner/Debug/ops.exe [host:port]
```

Flutter for Windows is in `H:\flutter` (`make` sets the path and `PUB_CACHE=H:\pub-cache`).

## Modes

- **Pull request**: base and head branches, commits, files changed, unified diff; click a line to
  show it in Neovim.
- **Changes**: working tree vs HEAD; stage, unstage, discard files and hunks; commit.
- **Tasks**: Linear-style workspace over `backlog/` and `openspec/`: inbox, task list and board
  views, change details with requirement cards, archive into the living spec, specs, milestones,
  legacy notes with Promote, Review a task's branch with its Verify list beside the diff, New change
  drafted by an agent.

Keys in Tasks: J/K move, Enter open, Esc close, / filter, C new task, S/P cycle status/priority,
Ctrl+K palette.

## Tests

```
make test     # unit tests, plus integration tests against a headless Neovim
```
