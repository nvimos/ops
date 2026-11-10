# Plan: nvimos-poc-frontend

A Flutter desktop app for Windows, in the style of GitHub Desktop, for reviewing what agents did
overnight. It shows two branches as a pull request, plus the working tree with staging, and stays
in sync with a running Neovim. Original requirements:
`~/es/nvimos-meta/poc-nvim-backend/flutter.md`. All editor and git state comes from the backend
plugin, `~/es/nvimos-poc-backend` (see its PLAN.md for the protocol).

## Decisions

| Topic       | Choice                                                                             |
|-------------|------------------------------------------------------------------------------------|
| Platform    | native Windows app; Flutter in `H:\flutter`, Visual Studio 2022 C++ tools          |
| Connection  | TCP 127.0.0.1:6666 (`nvim --listen` or `:NvimosServe`); Dart can't open named pipes |
| Git         | the app runs no git itself; everything goes through the backend's `git.*`          |
| Modes       | both from the start: branch review (PR) and working tree vs HEAD                   |
| Repo layout | one checkout; agent work is on branches                                            |
| Click       | working tree: `open(path, line)`; branch review: `show(head, path, line)`, a read-only buffer (default, still open) |
| Editing     | only in Neovim, never in the app                                                   |

## Architecture

- `rpc/`: msgpack-RPC client over a TCP socket: requests with ids, responses, notifications as a
  stream. Uses the `msgpack_dart` package or a small encoder of its own; `dart_nvim_api` only if it's
  maintained.
- `backend/`: typed wrapper around the plugin: `attach`, `resync`, `getText`, `open`, `show`, `git.*`;
  turns `nvimos` notifications into typed events, checks `seq` per domain and resyncs on a gap.
- `model/`: buffers, current window and cursor, diagnostics, git state (branches, status, PR diff).
  A git `changed` hint re-queries what the current view shows, debounced.
- `ui/`: the views below. State management with plain `ChangeNotifier`s, no framework.

## Views

- Left sidebar: repo name, current branch, a mode switch (Pull request / Changes).
- **Pull request**: base and head pickers, commit list of `base..head`, file tree of the changed
  files with +/- counts, unified diff of the selected file, like GitHub's "Files changed" tab.
  Click a file or hunk line: Neovim shows that line.
- **Changes**: staged and unstaged files with checkboxes, the selected file's hunks with stage,
  unstage and discard buttons, commit message and Commit button. Click a line: Neovim opens it.
- Status bar: connection state, Neovim's current file and cursor (live).
- Mouse first, keyboard optional. Side-by-side diff and syntax colors come later.

## Steps (one commit each)

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
12. README: how to run (`nvim --listen 127.0.0.1:6666`, `flutter run -d windows`).

## Open

- Branch review click target: read-only branch copy (default) or check out the branch first.
- Flutter on exFAT (`H:`): if builds fail on symlinks or file locks, move the SDK to an NTFS drive.
