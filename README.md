# Ops

[![ops test](https://github.com/nvimos/ops/actions/workflows/test.yml/badge.svg)](https://github.com/nvimos/ops/actions/workflows/test.yml)

A Flutter Windows app for reviewing repositories locally, with an optional Neovim connection for the live editor and remote checkouts. Plan: [PLAN.md](PLAN.md).

Backend: [relay](https://github.com/nvimos/relay), the Neovim plugin used by the remote backend
[![relay test](https://github.com/nvimos/relay/actions/workflows/test.yml/badge.svg)](https://github.com/nvimos/relay/actions/workflows/test.yml)

## Run

```
make run      # the app; or build/windows/x64/runner/Debug/ops.exe [directory | host:port]
make nvim     # optional: Neovim on 127.0.0.1:6666 with the backend plugin
```

A directory opens locally with no Neovim. An address connects to a Neovim running relay, for the
editor and the remote use case. The Connect screen offers both Open folder and Connect to Neovim.

Flutter for Windows is in `H:\flutter` (`make` sets the path and `PUB_CACHE=H:\pub-cache`).

## Modes

- **Pull request**: base and head branches, commits, files changed, unified diff; click a line to
  show it in Neovim when one is connected.
- **Changes**: working tree vs HEAD; stage, unstage, discard files and hunks; commit.
- **Add and Ignore**: the file-first list: add, untrack, ignore and delete, with the ignore pane.
- **Tasks**: Linear-style workspace over `backlog/` and `openspec/`: inbox, task list and board
  views, change details with requirement cards, archive into the living spec, specs, milestones,
  legacy notes with Promote, Review a task's branch with its Verify list beside the diff, New change
  drafted by an agent.
- **Repos**: the repositories found around the current folder, with start-dirs as hints.
- **Settings**, **Log**, **Help**.

Keys in Tasks: J/K move, Enter open, Esc close, / filter, C new task, S/P cycle status/priority,
Ctrl+K palette.

## Tests

```
make test     # unit tests, plus integration tests against a headless Neovim
```
