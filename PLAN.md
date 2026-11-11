<!-- vim: set nowrap fdm=marker: -->

---

# Plan: nvimos-poc-frontend

A Flutter desktop app for Windows. Linux, Android and Macos versions will be implemented later.

All editor and git state comes from the backend plugin, `~/es/nvimos-poc-backend`, see _that_ PLAN.md for the protocol.

## Main functionality

- In the style of GitHub Desktop, present two local branches for reviewing as a pull request.
  For example, what llm-agents did overnight.
  This is the Pull request mode.

- The Changes mode shows current working tree changes against HEAD.
  In other words, local changes.

- The Tasks mode imitates the commercial app Linear, doing more or less the same thing,
  but using the markdown files of openspec and backlog.md as a database of sorts

- The Directories mode picks the Active Directory, the repo the other modes work on.

## Original app description

The initial idea is in these files. They are the foundation and give agents context
when building or improving a version, and they will be revised over time.
Where they disagree with this plan, the plan wins.

- `~/es/nvimos-meta/poc-nvim-backend/flutter.md`
- `~/es/nvimos-meta/poc-nvim-backend/flutter-project-man.md`

## Conventions

### Not normative

A section marked _not strictly normative_ describes the current implementation
and the desired behavior for a future one, but it is not a requirement.
An agent may follow it or implement something better.

## General requirements

- The app is continuously in sync with a running Neovim instance that serves as the backend.
- Any errors from the backend should replace their view or ui-element and be selectable text (the trace).
  - errors from actions (stage, commit, archive, ...) show as a short snackbar
    with a Details link that opens the selectable trace

- The Mouse is the main input device. All actions are mousable.

- Keyboard inputs for navigation, switching modes, toggling or selecting items
  - use imagination if needed or follow vim/neovim conventions
  - or/and interpret how vimium does things
  - or/and interpret how vifm does things
  - imagining/interpreting keys applies if the spec does not says which keys to use and how and what for

### Keys

Draft, from vim, fugitive and vifm conventions. "today" marks keys the app already has.
Keys act on the focused pane; while a text field has focus, keys type into it,
except Esc (leave the field) and Enter (confirm).

<!-- {{{ keys -->

Global

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `M-]` / `M-[`      | next / previous mode (next is down the rail)            |
| `M-1` … `M-5`      | mode by its place on the rail                           |
| `Ctrl+B`           | expand / collapse the sidebar                           |
| `Ctrl+K`           | command palette: every action and record (today: Tasks) |
| `?`                | the Help mode: this key table                           |
| `Tab` / `S-Tab`    | focus next / previous pane                              |
| `/`                | filter the focused list (today: Tasks)                  |
| `Esc`              | leave the filter, close a panel, undo a narrowing       |

Any list (files, commits, branches, dirs, tasks)

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `j` / `k`, arrows  | next / previous item (today: Tasks)                     |
| `gg` / `G`         | first / last item                                       |
| `Ctrl+D` / `Ctrl+U`| half a page down / up                                   |
| `Enter`            | open or pick the item (today: Tasks)                    |
| `l` / `h`          | expand / collapse a folder                              |
| `zR` / `zM`        | expand / collapse all folders                           |
| `o`                | open the item in Neovim, like a click                   |

Pull request

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `gb` / `gh`        | focus the base / head picker                            |
| `gs`               | swap base and head                                      |
| `]f` / `[f`        | next / previous file                                    |
| `]c` / `[c`        | next / previous hunk                                    |
| `v`                | unified / side-by-side                                  |
| `zw`               | toggle line wrapping                                    |
| `Enter` on a commit| narrow to that commit; `Esc` returns to the full range  |

Changes

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `-`                | stage or unstage the file or hunk under the cursor      |
| `s` / `u`          | stage / unstage                                         |
| `X`                | discard (asks first)                                    |
| `cc`               | focus the commit message                                |
| `Ctrl+Enter`       | commit (in the message field)                           |

Tasks

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `c`                | new task (today)                                        |
| `s`                | cycle the status (today)                                |
| `p`                | cycle the priority (today)                              |
| `Esc`              | close the detail panel (today)                          |

Directories

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `Enter`            | make the dir the Active Directory                       |
| `n`                | toggle "New Neovim per directory"                       |

<!-- }}} -->


### How errors are shown now:

_not strictly normative_ <!-- {{{ -->

- An error Neovim returns for a request becomes an `NvimError` (`lib/rpc/client.dart`)
  - `message` is Neovim's full text, including the Lua `stack traceback`
  - `short` cuts the traceback and the `Lua:` / `Vim:` / `nvimos:` prefixes
  - `toString()` gives `NvimError(<method>): <message>`, the full text with the trace.
- Loading errors replace the view, with the trace
  - Pull request: `PrState` keeps `'$e'` in `error`,
    and `PrView` shows it in place of the diff (`lib/ui/pr_view.dart:111`)
  - Tasks: `Workspace` keeps `'$e'` in `error`,
    and `TasksView` shows it while nothing is loaded (`lib/ui/tasks/tasks_view.dart:503`)
  - both go through `Empty` (`lib/ui/widgets.dart`): centered small muted `Text`,
    which is not selectable.
- Action errors show as a snackbar at the bottom, without the trace
  - stage, unstage, discard, commit, open/show in Neovim, task edits, archive, new task/change
  - they run through `Session.run`, which returns `NvimError.short`
  - the snackbar disappears after a few seconds, and its text is not selectable.
- Connection errors show under the address field on the connect screen, without the trace
  - `Session` keeps `NvimError.short`, or "no Neovim listening on <address>" for a refused socket
  - plain `Text`, not selectable.
- Changes: `ChangesState` keeps loading errors in `error`, but `ChangesView` never shows it;
  the view stays as it was.
<!-- }}} -->

## Decisions

_not strictly normative_

Initial one shot vibe code decisions (this section will disappear, it serves as notes, or running ideas).

| Topic       | Choice                                                                             |
|-------------|------------------------------------------------------------------------------------|
| Platform    | native Windows app; Flutter in `H:\flutter`, Visual Studio 2022 C++ tools          |
| Connection  | TCP 127.0.0.1:6666 (`nvim --listen` or `:NvimosServe`); Dart can't open named pipes |
| Git         | the app runs no git itself; everything goes through the backend's `git.*`          |
| Editing     | Primarily in Neovim if it's open as a non-headless instance |

## Architecture

This section describes where the code lives and what the responsibilities of the different directories are

Everything is under `lib/`; `main.dart` reads the address and starts the app.

- `rpc/`
  - `client.dart`: msgpack-RPC client over a TCP socket
    - requests with ids, responses, notifications as a stream
    - `NvimError` for errors Neovim returns (full message and a `short` form)
  - `msgpack.dart`: its own msgpack encoder and streaming decoder, no package

- `backend/`
  - `backend.dart`: typed wrapper around the plugin, one RPC connection
    - checks the backend API version on connect
    - `attach`, `getText`, `open`, `show`
    - `git.*`: branches, log, diff, status, stage/unstage/discard (file and hunk), checkout, commit
    - `files.*`: list, read, set lines, move, create, run a CLI
    - `jobs.*`: start and cancel
    - turns `nvimos` notifications into typed events, checks `seq` per domain, resyncs on a gap
  - `models.dart`: typed views of the plugin's maps (cursor, branches, commits, diffs, status, jobs)

- `state/`: `ChangeNotifier`s, no framework
  - `session.dart`: the connection, retries, and the live state every view shares:
    current window and cursor, repo info, jobs, git change hints
  - `pr.dart`: Pull request state: branches, base and head, commits, the diff
  - `changes.dart`: Changes state: working tree status, the selected file's diff, actions
  - `prefs.dart`: small per-user settings in `%APPDATA%/nvimos/state.json`
  - a git hint from the backend makes each state re-query what it shows

- `tasks/`: the Tasks mode's data, pure Dart
  - `parse.dart`, `markdown.dart`, `model.dart`: Backlog.md tasks, OpenSpec changes,
    living specs, legacy notes, milestones
  - `workspace.dart`: loads the planning files through the backend, links them,
    reloads on git hints
  - `edits.dart`: line-level edits that refuse to apply if the file changed meanwhile
  - `archive.dart`, `inbox.dart`: archiving a change into its spec, the inbox

- `ui/`
  - `shell.dart`: the window, mode rail, status bar
  - `connect.dart`, `pr_view.dart`, `changes_view.dart`, `tasks/`: the views below (aka Modes)
  - `diff_view.dart`, `file_tree.dart`, `widgets.dart`, `theme.dart`: shared pieces

- `test/`: unit tests per state and parser; `test/support/nvim.dart` runs a headless Neovim
  with the backend for the RPC and backend tests.

## The UI

Description of the UI.

- Initial view (Connect to Neovim)
  <!-- {{{ initial view -->
  - shown in place of the current mode whenever the app is not connected, at startup and after Neovim goes away
  - the mode rail on the left and the status bar stay visible
  - the address comes from the first command-line argument, else `NVIMOS_ADDR`, else `127.0.0.1:6666`
  - the app connects on startup without waiting for a click
  - an address field with a Connect button; Enter in the field also connects
  - a new address drops the current connection and connects there
  - while connecting, the button reads "Connecting…" and is disabled
  - a failed attempt shows a short reason under the field:
    "no Neovim listening on <address>", "the nvimos plugin is not loaded in this Neovim"
    or a backend API version mismatch
  - after a failure or a lost connection the app retries every 2 seconds, forever
  - a lost connection shows "Neovim went away" and returns to this view
  - a box with the ways to start the backend, selectable for copying:
    `nvim --listen 127.0.0.1:6666`, `:NvimosServe` in a running Neovim,
    `make nvim` in this repo
  - once connected, the app subscribes to buffers, windows, git and jobs,
    and the selected mode replaces this view.
  <!-- }}} -->

### Left sidebar (mode rail)

<!-- {{{ sidebar -->
- a narrow strip, 48 px wide, on the left edge of the window
- the top item is a toggle that expands and collapses the sidebar
  - expanded, each icon gets a short label beside it, so the sidebar stays narrow
  - hovering an icon or label shows a brief explanation of the mode,
    like an HTML `title` tooltip.
- one icon per mode, top to bottom: Pull request, Changes, Tasks, Directories, Help
- Help lists every key the app has; it works without a connection too
- collapsed: icons only, hovering shows the mode name as a tooltip;
  expanded: hovering shows the brief explanation (see above)
- the selected mode has an accent bar on its left edge and a brighter icon
- a click switches the mode
  - <M-]> and <M-[> go to previous / next mode. next is down
- visible at all times, also while not connected; a mode picked then shows once the app connects
- modes stay alive in the background, so switching back keeps their selection and scroll position
- no repo name and no current branch here; the current branch is in the status bar.
- Directories mode, a folder icon
  - its icon comes after all other mode icons, not anchored to the bottom of the rail
  - see "Directories mode" below
<!-- }}} -->

### Status bar

<!-- {{{ status bar -->
- appears at the bottom of the app
- Active Directory, current branch, Neovim's current file and cursor (live), connection state
<!-- }}} -->

### Views (Modes)

#### Pull request ("Review")

- layout
  <!-- {{{ -->
  - three columns, left to right
    - left pane, 300 px fixed
      - Base Picker - a Swap button (swaps base and head)
      - Head Picker
      - Files Changed
      - Commits list
    - main pane, takes the remaining width (diff view)
      - header: status icon, file path (old → new for renames), +/− of the file
      - unified diff of the selected file below it, scrolls
      - or a centered message instead: an error, "Pick two different branches.",
        "Loading…", "No changes between these branches.", "Pick a file."
  - thin dividers between the columns and between the left pane's sections
  <!-- }}} -->

- base and head pickers 
  <!-- {{{ -->
  - commit/branch list that is used by git to show the diffs, the  `base..head` parameter
  - lists the local branches; any revision git accepts can also be typed:
    a sha, a tag, `HEAD~3`
  - the list is filterable. when only one item is left by filter, it is automatically selected and the focus moves to the next picker
  - when both pickers are selected, we show the diff view
  <!-- }}} -->


- commits
  - the list of commits appears below the list of files <!-- {{{ -->
  - the list of commits is collapsible
    - the header of the commits, remains visible
    - clicking on it either collapses or expands the list of commits
  - a COMMITS section in the left pane, below FILES CHANGED
    - today: above FILES CHANGED, right under the pickers
  - the header shows the count and a small spinner while loading
  - the commits of `base..head`: what head has that base doesn't, newest first,
  - one row per commit: short sha in faint mono, then the subject, cut off with an ellipsis
    - this text is selectable
  - hovering a row shows short sha, author and age ("3h ago", "2d ago")
  - at most 6 items/rows tall, scrolls beyond that
    - if the file list and commits are competing for vertical space the list of commits only shows 3 items and remains scrollable
  - clicking a row narrows the file tree and the diff to that one commit;
    clicking it again or Esc returns to the full `base..head` range
    - today rows don't react to clicks
  - reloaded together with the diff when a picker changes or git state changes.
  <!-- }}} -->

- file and directory tree
  - file tree of the changed files with +/- counts
  - a button in its header expands / collapses all dirs;
    the current file's dir stays expanded up to the relevant level

- the commits and files/dirs panels should have a button to make them the "dominant item"
  - when dominant they take as much space as they can vertically, but not forcing the other elements out completely
  - the dominant choice and the collapsed state last for the session; every start begins with files dominant

- diff views (next main panel)
  <!-- {{{ -->
  - switching view keeps the active file and shows it after switching
  - both view have a row of actions or toggles at the top
    - toggle line wrapping
  - switching side-by-side and unified: when the PR mode is selected, the sidebar rail gets
    two items under the pull request icon, one per view, unified first, then side-by-side
  - unified diff of the selected file, like GitHub's "Files changed" tab.
  - Side-by-side diff and syntax colors come later.
  <!-- }}} -->
- Click a file or hunk line: Neovim opens that line in the current buffer
  - head checked out: the working tree file
  - head not checked out: a read-only copy of the file at head (deleted lines: at the merge base)
  - the current buffer has unsaved changes: open in a new window instead


#### Changes ("WIP")

staged and unstaged files with checkboxes, the selected file's hunks with stage,
unstage and discard buttons, commit message and Commit button. Click a line: Neovim opens it.


#### Tasks mode ("Folio")

A Linear-style workspace for the repo's OpenSpec and Backlog.md files: 
sidebar, issue list, detail panel from the right, inbox with
"Needs attention", requirement cards with Added/Modified/Removed pills,
no raw Markdown,
keyboard J/K/Enter/Esc/C and /.

- `tasks/parse.dart`, `tasks/markdown.dart`: pure Dart parsers with unit tests: Backlog.md task
  (YAML header, sections, checklists), OpenSpec change (proposal, tasks.md Build/Verify, design,
  spec deltas split on ADDED/MODIFIED/REMOVED/RENAMED), living spec, legacy notes, `index.tsv`.
- `tasks/workspace.dart`: loads the `backlog/`, `openspec/` and `legacy/` files through the
  backend's `files.*` (unsaved Neovim edits show too), links tasks and changes, reloads on git hints.
- `tasks/edits.dart`: line-level edits (status in YAML header, checkbox toggle, Status line in
  proposal) sent as `files.set_lines`; each refuses if the line changed meanwhile.
- archiving a change (`Workspace.archive`): `openspec archive` when the CLI is installed,
  else merge its deltas into the living spec (`tasks/archive.dart`) and move the folder
  as `files.move`; new tasks and promoted legacy notes are written as `files.create`.
- UI: sidebar (Inbox, Tasks, Changes, Specs, Legacy, Milestones), list with grouping, detail panel.

#### Directories mode

<!-- {{{ -->
- works only while connected; disconnected, the view says so
- lists the start dirs of the genja-startdirs plugin,
  in the same order as its Telescope picker (`:Telescope mydirs`, by frecency)
  - without genja-startdirs: the dirs of Neovim's recent files (`v:oldfiles`), most recent first
  - the backend provides the list, the app reads no files itself
- picking a dir doesn't count as a use; frecency stays as Neovim records it
- the list is filterable;
  when the filter leaves one item, it is selected and becomes the Active Directory.
- clicking an item selects it as the Active Directory
- the Active Directory
  - default: the connected Neovim does `:cd` there; the backend follows the cwd,
    sends a new git snapshot and every mode reloads
  - a toggle in this view, "New Neovim per directory": picking a dir starts a new Neovim
    instance there and the app connects to it
<!-- }}} -->


## non-functional remarks

A Note on cloning or imitating Github Desktop and Linear. The author is grateful to both companies for creating those
products and their vision, of how things work, with utmost humility and gratitude.

##  implementation details

_not strictly normative_ 

## Open questions

_not strictly normative_ 

- Flutter on exFAT (`H:`): if builds fail on symlinks or file locks, move the SDK to an NTFS drive.

### Steps (one commit each)

_not strictly normative_ 

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
