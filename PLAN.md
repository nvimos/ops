<!-- vim: set nowrap fdm=marker: -->

---

# Plan: Ops (nvimos-poc-frontend)

A Flutter desktop app for Windows. Linux, Android and Macos versions will be implemented later.

All editor and git state comes from the backend plugin, relay (`nvimos/relay`, checkout `~/es/nvimos-poc-backend`),
see _that_ PLAN.md for the protocol.

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

From vim, fugitive and vifm conventions; all built. The Help mode (`?`) lists them in the app.
Keys act on the focused pane; while a text field has focus, keys type into it,
except Esc (leave the field) and Enter (confirm).

<!-- {{{ keys -->

Global

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `M-]` / `M-[`      | next / previous mode (next is down the rail; the mouse  |
|                    | wheel over the rail does the same)                      |
| `M-1` … `M-5`      | mode by its place on the rail                           |
| `Ctrl+B`           | expand / collapse the sidebar                           |
| `Ctrl+K`           | command palette: every action and record (Tasks)        |
| `?`                | the Help mode: this key table                           |
| `b`                | show / hide the debug bar                               |
| `Ctrl+Arrow`       | jump to the pane in that direction (PR: head picker,    |
|                    | FILES, COMMITS, diff, the rail; Changes: STAGED,        |
|                    | CHANGES, message, diff, the rail)                       |
| `Tab` / `S-Tab`    | next / previous stop, in visual order (left column top  |
|                    | to bottom, then the right), wrapping round, as in a     |
|                    | Windows or HTML page. PR: base, head, files, commits,   |
|                    | diff. Changes: STAGED, CHANGES, commit message, diff.   |
|                    | Tasks and Directories: filter, list. The mode rail is one|
|                    | stop in front of the first (not each mode in it)        |
| `/`                | filter the list (Tasks, Directories)                    |
| `.`                | widen or narrow the detail panel (Tasks)                |
| `Shift`+wheel      | over the Facets or the task list: previous / next item  |
| middle click       | over the Facets or the task list: the wheel steps items (like Up / Down) or scrolls |
| `Esc`              | leave the filter, close a panel, undo a narrowing       |

Any list (files, commits, branches, dirs, tasks)

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `j` / `k`, `Down` / `Up` | next / previous item; in a diff, scroll 3 lines   |
| `S-Up` / `S-Down`, `K` / `J` | in a diff, scroll 10 lines                     |
| `{` / `}` (Shift+[ / Shift+]) | three items up / down in a list (PR, Changes, |
|                    | Tasks, Directories); no hop to another pane             |
| `h` / `l`, `Left` / `Right` | from a list to the diff / back (PR, Changes)    |
| `Down` past the last item | the pane visually below the list; `Up` past the    |
|                    | first item: the pane above (PR: head picker, FILES,     |
|                    | COMMITS; Changes: STAGED, CHANGES, commit message)      |
| `gg` / `G`         | first / last item                                       |
| `Ctrl+D` / `Ctrl+U`| half a page down / up                                   |
| `Enter`            | open or pick the item                                   |
| `zo` / `zc`        | unfold / fold the selected file's folder (PR files)     |
| `zR` / `zM`        | expand / collapse all folders                           |
| `o`                | open the item in Neovim, like a click                   |

Pull request

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `i`, `gi` / `2gi`  | focus the base picker / the head picker (go input)      |
| `gs`               | swap base and head                                      |
| `[f` / `]f`        | previous / next file                                    |
| `]c` / `[c`        | next / previous hunk                                    |
| `v`                | unified / side-by-side (also in Changes)                |
| `zw`               | toggle line wrapping                                    |
| `Enter` on a commit| narrow to that commit; `Esc` returns to the full range  |

Changes

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `]c` / `[c`        | next / previous hunk; the keys below then act on it     |
| `-`                | stage or unstage the current hunk, or the file          |
| `Space` / `u`      | stage / unstage the current hunk, or the file           |
| `X`                | discard (asks first)                                    |
| `cc`               | focus the commit message                                |
| `Ctrl+Enter`       | commit (in the message field); `Esc` back to the files  |

Tasks

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `c`                | new task                                                |
| `t`                | cycle the status                                        |
| `p`                | cycle the priority                                      |
| `A`                | this project / all projects (shared planning folder)    |
| Ctrl+click a file  | open it in a new nvim-qt (detail panel)                 |
| `Esc`              | close the detail panel                                  |

Directories

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `Enter`            | make the dir the Active Directory                       |
| `n`                | toggle "New Neovim per directory"                       |

<!-- }}} -->


### How errors are shown now

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
  - `session.dart`: the connection, Start Neovim, and the live state every view shares:
    current window and cursor, repo info, jobs, git change hints
  - `pr.dart`: Pull request state: branches, base and head, commits, the diff
  - `changes.dart`: Changes state: working tree status, the selected file's diff, actions
  - `nvim_launcher.dart`: finds the backend checkout and starts Neovim in its own console
  - `diff_prefs.dart`: the diff layout, wrapping and scroll steps, shared by Pull request and Changes
  - `prefs.dart`: small per-user settings in `%APPDATA%/nvimos/state.json`
  - a git hint from the backend makes each state re-query what it shows

- `tasks/`: the Tasks mode's data, pure Dart
  - `parse.dart`, `markdown.dart`, `model.dart`: Backlog.md tasks, OpenSpec changes,
    living specs, legacy notes, milestones
  - `workspace.dart`: loads the planning files through the backend, links them,
    reloads on git hints, filters them by project
  - `sorter.dart`: the sorting modes and direction of a list (the buttons are `SortButtons` in `ui/tasks/tasks_nav.dart`)
  - `edits.dart`: line-level edits that refuse to apply if the file changed meanwhile; the checkbox
    mark cycle (open, x, ., ~, n) of the Neovim tilde plugin
  - `archive.dart`, `inbox.dart`: archiving a change into its spec, the inbox

- `timing/ui_timing.dart`: UI timing instrumentation (see Performance)

- `ui/`
  - `shell.dart`: the window, mode rail, status bar
  - `connect.dart`, `pr_view.dart`, `changes_view.dart`, `tasks/`: the views below (aka Modes)
  - `diff_view.dart`, `file_tree.dart`, `widgets.dart`, `theme.dart`: shared pieces
  - `nav_keys.dart`: the one mapping of arrows, hjkl and WASD to directions
  - `key_sequence.dart`: two-key commands with counts (`gg`, `]f`, `2gi`)
  - `reveal.dart`: keeps a list's selected row in view from the real render positions
  - `resizable_pane.dart`: a left pane the user drags wider or narrower
  - `wheel_mode.dart`: the mouse wheel over a list: scroll, or step through items (middle click)
  - `debug_bar.dart`: the debug bar and the role names of focused elements
  - `mode_rail.dart`, `help_view.dart`, `status_bar.dart`: the rail, the Help mode, the status bar

- `test/`: unit tests per state and parser; `test/support/nvim.dart` runs a headless Neovim
  with the backend for the RPC and backend tests.

## The UI

Description of the UI.

### Layout of the window

_not strictly normative_

<!-- {{{ layout -->
The window is one column: the mode area (everything above the bars), the debug bar when it is
on, and the status bar. The debug bar is a pane, not an overlay: it takes its height from the
mode area, which shrinks upward.

```
┌────┬───────────────────────────────────────────────────────────────┐
│    │ Mode area                                                     │
│    │ ┌───────────────┬──────────────────────────────┬────────────┐ │
│ R  │ │ Left pane     │ Main pane                    │ Review     │ │
│ a  │ │               │                              │ panel      │ │
│ i  │ │ Revision      │ Diff                         │ (only when │ │
│ l  │ │ pickers       │                              │ reviewing) │ │
│    │ │               │                              │            │ │
│    │ │ Files         │                              │            │ │
│    │ │               │                              │            │ │
│    │ │ Commits       │                              │            │ │
│    │ └───────────────┴──────────────────────────────┴────────────┘ │
├────┴───────────────────────────────────────────────────────────────┤
│ Debug bar (when on)                                                │
├────────────────────────────────────────────────────────────────────┤
│ Status bar                                              [bug]      │
└────────────────────────────────────────────────────────────────────┘
```

- the rail is as high as the mode area; the two bars span the whole width
- Pull request and Changes have the left pane (resizable), the main pane and, while reviewing, the
  review panel; Changes' left pane holds Staged, Changed and the commit message instead
- Tasks, Directories and Help fill the mode area with one pane
- the bug button at the right end of the status bar shows and hides the debug bar
<!-- }}} -->

- Search and filter fields (Tasks, Directories, branch pickers, command palette, Help) have an x at
  the right edge while they hold text; a click clears the field (`ClearButton` in `ui/widgets.dart`)
  - Alt+X in such a field does the same, and refreshes what it filters, so the filtering resets
  - Left in a filter moves the text cursor; at the leftmost edge, or in an empty field, it goes to
    the pane on the left (the mode rail; in Tasks the Facets)

- Lists keep the selected row in view
  - how: the row's real position is read from the render tree (`revealIndex` in `ui/reveal.dart`);
    a row that is not built yet is reached by the average height of the rows that are, frame by
    frame, until it exists
  - no row height is written down anywhere, because heights change with the font size, which is
    meant to become a setting; the folder rows (25 px) and file rows (29 px) of today are not used
  - found by a bug: an assumed 24 / 26 px per row left the last file, in a folder at the end of
    the list, below the pane

- Initial view (Connect to Neovim)
  <!-- {{{ initial view -->
  - shown in place of the current mode whenever the app is not connected, at startup and after Neovim goes away
  - the mode rail on the left and the status bar stay visible
  - the address comes from the first command-line argument, else `NVIMOS_ADDR`, else `127.0.0.1:6666`
  - the app tries to connect once on startup without waiting for a click
  - an address field with a Retry button; Enter in the field also connects
  - a new address drops the current connection and connects there
  - while connecting (or while a Neovim start waits to connect) the button reads "Cancel";
    it ends the attempt at once and shows "connecting cancelled"; the start buttons work again
  - an attempt gives up after 8 s with "no answer from <address> within 8 s" (a listener that
    accepts but never answers: a hung Neovim, another program); its socket is closed
  - a failed attempt shows a short reason under the field:
    "no Neovim listening on <address>", "the nvimos plugin is not loaded in this Neovim"
    or a backend API version mismatch
  - after a failure or a lost connection the app does not retry by itself; Retry tries once more
  - buttons that start Neovim, then connect
    - Start Neovim: `nvim` in its own console window
    - Start nvim-qt: the GUI, with `-platform windows:darkmode=1` and the config's
      `%LOCALAPPDATA%
vim
vim-qt.qss` as `-stylesheet` when it exists; nvim gets the rest after `--`
    - Start headless: `nvim --headless`, detached from the app: no window, no terminal,
      keeps running after the app quits
    - each listens on the address, with the backend plugin loaded after the config, like `make nvim`
    - the plugin checkout is `NVIMOS_BACKEND`, else a `relay` or `nvimos-poc-backend` folder
      holding `plugin/nvimos.lua`, next to a parent folder
      of the working directory or of the exe
    - the pressed button reads "Starting…" while the app waits up to 12 s for it to listen
      (3 s per connect attempt); then "Neovim did not listen on <address> within 12 s"
    - when something already accepts connections on the address, nothing is started and the
      field says "<address> is taken by a program that does not answer as Neovim with the
      nvimos plugin; close it or use another address"
    - every failure on this path (a launcher exception included) ends as text under the field,
      and the buttons never stay disabled for good
    - "nvim is not on PATH" (or nvim-qt) or a missing plugin checkout show under the field
  - a Stop headless button stops every `nvim.exe --headless` of this user, found in the process list
    - "stopped <n> headless Neovim" or "no headless Neovim running" shows under the field
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
  - the key groups fill the pane in columns about 360 px wide, as many as the width allows,
    so every key fits on one screen; the groups keep their order and the columns even out in height
  - a narrow pane gets fewer columns and scrolls
  - the text is selectable
  - each key row: the keys, then the description right after them; the key column is as wide as the
    group's widest key, so descriptions line up inside a group and sit close to their keys
  - key labels: every key in the accent colour; the `+` of a chord and the `,` between alternatives
    in a near-background colour; arrows as thin chevron icons; no slash between keys: single keys
    that go together are written together (`jk`, `hl`), longer ones are separated by a space
    (`gg  G`, `[c  ]c`); the left bracket comes first
  - descriptions are words ("next or previous item"), not slashes; the navigation rows just say
    "navigate", the Shift row "scroll fast"; Tab and Shift+Tab are two rows
  - typing anywhere searches: the matches of the typed text are highlighted in keys, descriptions
    and group titles; `/` empties the field and the highlights, Esc empties it and leaves, Enter
    leaves and keeps the highlights
- collapsed: icons only, hovering shows the mode name as a tooltip;
  expanded: hovering shows the brief explanation (see above)
- the selected mode has an accent bar on its left edge and a brighter icon
  - Pull request and Changes show their two views under the mode; the mode and both views carry the
    accent bar, 2 px wide, and the current view's bar is twice as wide (4 px)
- the mouse wheel over the rail steps to the previous or next mode, like Alt+[ and Alt+], round the ends
- the rail is one stop in the Tab cycle, in front of the first pane (not each mode in it)
  - while it has the keyboard, a cursor starts on the current mode; Up / Down move it over the
    expand / collapse button and the modes; Enter, Right or Space presses the button, or switches
    to the mode and goes into it; Esc goes back
- a click switches the mode
  - `<M-]>` and `<M-[>` go to previous / next mode. next is down
- visible at all times, also while not connected; a mode picked then shows once the app connects
- modes stay alive in the background, so switching back keeps their selection and scroll position
- no repo name and no current branch here; the current branch is in the status bar.
- Directories mode, a folder icon
  - its icon comes after all other mode icons, not anchored to the bottom of the rail
  - see "Directories mode" below
<!-- }}} -->

### Debug bar

<!-- {{{ debug bar -->
- for finding out where the focus goes; off at start, toggled with the bug button in the status bar
  or the `b` key (not while typing in a field, and not in Help, where `b` is search text)
- a pane above the status bar that takes its height from the mode area (not an overlay)
- three lines high; items stack three to a column and continue in the next column, so it never
  becomes one long line
- each item is "Label: value" with the colons of a column on one line:
  - Focus: the focused element by its role in the interface (not its class), e.g. "Commits list",
    "Base revision field", "Mode rail", "Task detail"
  - Mode, then the mode's state: in Pull request the commit under the cursor ("3 of 8" and its
    short hash), file and hunk; in Changes file (staged or not) and hunk
  - Key: the last key pressed
  - Mouse: the last mouse event: a button going down or up (Left, Middle, Right) and the wheel
    (down, up), with the modifiers held; moves are not shown
  - the bar reads the focus and the mode's state again after every key, click and wheel step
  - a click in a pane makes it the active pane, as a key that goes there does (Pull request: files,
    commits, diff; Changes: STAGED, CHANGES; Tasks: Facets, list), so "Focus" follows the mouse too
- roles come from a table (`focusRoles` and the pane tables in `ui/debug_bar.dart`): a focus node
  has a label, the label has a role; a node that serves several panes (Pull request, Changes,
  Tasks) takes its pane from the mode
<!-- }}} -->

### Status bar

<!-- {{{ status bar -->
- appears at the bottom of the app
- Active Directory, current branch, Neovim's current file and cursor (live), connection state
- at the right end, a bug button shows and hides the debug bar (see "Debug bar")
<!-- }}} -->

### Views (Modes)

#### Pull request ("Review")

- layout
  <!-- {{{ -->
  - three columns, left to right
    - left pane, resizable by dragging its right edge (double-click: back to automatic)
      - automatic width: the narrowest that shows all its text, between 150 and 360 px
      - Base Picker - a Swap button (swaps base and head)
        - base defaults to the checked-out branch (main or master only when HEAD is detached),
          head to the newest other branch
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
  - the list of all branches drops down when the field is clicked (a click again closes it), and
    when the user starts typing, where it shows the matches; it does not open when the keys land
    in the field (Tab, `i`, `gi`, `2gi`, Ctrl+Up)
  - Enter in a field that was not typed in keeps its value and moves on
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
    - the other list gets at most 6 rows, or 3 when the dominant one would not fit
  - the dominant choice and the collapsed state last for the session; every start begins with files dominant
- both lists behave alike, and so do STAGED and CHANGES in the Changes mode
  (`ListPair`, `lib/ui/list_pair_view.dart`):
  - a click on the header folds or unfolds the list; the header stays
  - a folded dominant list hands the room to the other one
  - file trees have the expand / collapse all folders button

- diff views (next main panel)
  <!-- {{{ -->
  - switching view keeps the active file and shows it after switching
  - both view have a row of actions or toggles at the top
    - toggle line wrapping
  - switching side-by-side and unified: when the PR or Changes mode is selected, the sidebar rail gets
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

- STAGED over CHANGES behave like the Pull request files and commits: foldable headers,
  the most-room button (CHANGES have it at start), expand / collapse all folders (zR / zM)
- unified and side-by-side diffs, like the Pull request mode
  - the rail shows the two views under Changes while it is selected; `v` switches
  - one choice for both modes (and the line-wrapping toggle, `zw`)
- the left pane is resizable, like in Pull request
  - drag its right edge with the mouse; double-click the edge for the automatic width
  - automatic width: the narrowest that shows all file, folder and header text and the commit
    button, between 160 and 384 px; dragging is limited to 70 % of the window
- the files are listed, and walked by the keys, in the order the tree shows them: files of the top
  folder first, then the folders, each sorted by path (not git's status order)
- panes: STAGED, CHANGES, the diff (and the commit message for Tab)
  - Right (l): from a list to the diff; Left (h): from the diff back to the list it came from
  - Up / Down (j / k): the previous / next file of the active list, in the order shown (top-level
    files, then folders); in the diff they scroll it 3 lines at a time, with Shift 10 (]c / [c still jump hunks)
  - past the last item, Down goes to the pane visually below (STAGED to CHANGES, CHANGES to the
    commit message); past the first, Up goes to the one above; never to the diff
  - Left (h, a) from a list, with no pane to its left, gives the keyboard to the mode rail
    - Tab and Shift+Tab visit the rail as one stop, before the first and after the last stop
    - in the rail, Up / Down (k, j, w, s) move a cursor over the modes, which starts on the current
      mode; Enter, Right (l, d) or Space switches to it and goes into it; Esc goes back
  - moving up into a list from a pane below it selects the lowest visible item, not the first or
    last one (COMMITS up to FILES CHANGED, CHANGES up to STAGED, the message up to CHANGES)
  - Tasks has three panes: the Facets (Inbox, task views, sources, labels: the ways to narrow the list), the list and the
    detail of the current task; Left and Right (h, l, a, d) go between them, the Facets' Left
    goes to the rail
    - the mouse wheel over the Facets scrolls the pane; a middle click on it switches the wheel to
      stepping through the entries like Up / Down (a thin accent line at the pane's bottom edge shows
      it), and a middle click again switches back (on the user's setup the middle button arrives as
      Shift+Insert, so that key over the pane toggles too: a local exception marked in
      `wheel_mode.dart`)
    - Shift + the wheel steps in either mode
    - the task list does the same, stepping the current task (`WheelMode`, `ui/wheel_mode.dart`)
    - Up / Down in the Facets make the next entry the current view
    - Right from the list goes to the current task's detail; there the direction keys move from
      element to element (buttons, fields, rows), not by lines; Left past the leftmost element
      goes back to the list; Tab visits the elements in order and on to the rail; Esc closes it
  - one special case for the user's layout: the key where D is on QWERTY is Right whatever letter
    it types (found by its scan code); no other key is matched by position
  - the arrow keys, h j k l and W A S D do the same (Tasks and Directories have no panes: only
    w / s there); the commands that had `s` and `a` moved: stage is Space in Changes, status is `t`
    and the project scope Shift+A in Tasks
  - the file and commit lists scroll to keep the selected row in view
  - Tab / Shift+Tab: STAGED, CHANGES, commit message, diff, wrapping round
  - entering a list selects its first file unless one of its files is selected
  - the active list has its title lit


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
- Checkboxes in the detail panel
  - the box and the text next to it are one target: the pointer cursor and a hover background show it
  - a left click ticks an open box and clears any other mark
  - Ctrl+click or a right click steps the mark round the order of the Neovim tilde plugin
    (`genja/ext/tilde.lua`): open, `x`, `.`, `~`, `n`, and open again
  - icons: `x` a ticked box (counts as done), `.` a box with a dot (in progress), `~` a box with a
    dash (partly done), `n` a crossed box, dimmed (will not do); only `x` counts as done
- Ticking the last open box moves the task on by itself (`tasks/auto_status.dart`)
  - every build step ticked (Acceptance Criteria, or a change's Build), hand checks left: Needs Test
  - every box ticked, Verify too: Done
  - only from To Do, In Progress or Needs Test; never out of Done or Dropped, never on unticking
  - a tick in a change's `tasks.md` moves its task, and the proposal's Status line and `index.tsv` with it
  - a snackbar says so ("TASK-17 is Done now"), with Undo
    - it goes away after 3 seconds
    - while the mouse is over it, it stays, and goes when the mouse leaves (`HoverDismiss`)
- archiving a change (`Workspace.archive`): `openspec archive` when the CLI is installed,
  else merge its deltas into the living spec (`tasks/archive.dart`) and move the folder
  as `files.move`; new tasks and promoted legacy notes are written as `files.create`.
- UI: sidebar (Inbox, Tasks, Changes, Specs, Legacy, Milestones), list with grouping, detail panel.
- The list header (`TaskListHeader`): the title and count on the left, the filter and the view's own
  buttons against the right edge with a margin, in every view
  - the task list: "Group by" menu, then the sort buttons
  - the Changes list: "New change", then the sort buttons
- Sorting (`tasks/sorter.dart`, `SortButtons`): the list is sorted, two buttons control it
  - the direction button comes first: an up arrow for ascending, a down arrow for descending, a click reverses
  - the mode button follows: its icon is the current mode, a click goes to the next mode, round and round
  - a lowercase one-word label beside the icon names the mode; a click on the label is a click on the button,
    and the button keeps one width whichever word shows, so nothing beside it moves
  - hovering the mode button shows its full name in a tooltip (by name, by modification time, by creation
    time, by length of the title)
  - tasks cycle name, modified, created, length; Changes cycle id, name, modified, length
  - the default is modification time, newest first (descending)
  - the order holds inside each group, whatever the grouping; equal keys keep their order
  - creation time reads `created_date`; when over 80% of the tasks (from 5 tasks up) share one value it is
    not trusted: the order uses a date found inside the task instead (a label `created:YYYY-MM-DD`, else
    `created_at` or `created` in the header; how it is recorded is not settled), and the tooltip says the
    creation time is suspicious
  - any list can have the buttons: give it a `Sorter` and one `SortButtons`
- Milestones hold changes (`tasks/milestones.dart`)
  - a change goes to its task's `milestone:` (Backlog.md's field), archived or not
  - else, archived: the first dated milestone closing on or after its archive date
  - else: Next, the open one
  - dated milestones are the `## Name (YYYY-MM-DD)` sections of `milestones.md`,
    without it one per month of archive dates
  - a planned name not among them is a milestone of its own, listed under Planned with Next;
    `2027 Q1`, `2027-03` or `2027` give its closing date
- Facets labels: collapsed at first under a LABELS header that shows how many there are
  - the chevron expands and collapses the list
  - a click on the title sorts them by name or by number of tasks (most first); the header says which
- Detail panel header: Open in Neovim, widen, close
  - widen makes the panel twice as wide (at most the list's width) and lays it over the list,
    for long text; the list keeps its width underneath
  - the same button narrows it again; the width stays while you move between items
- Planning folder: the repo root, or the folder a `.nvimos` file at the repo root names
  - `.nvimos` holds `key = value` lines, `#` comments:
    `tracking = ../nvimos-meta` (`~`, absolute, or relative to the repo root) and `project = frontend`
  - the backend's `tracking.lua` reads it; `files.*`, the CLI and the planning watcher work in that folder
  - no `.nvimos`, or its folder is missing: the repo root, as before
  - Open in Neovim opens the file by its absolute path when the folder is outside the repo
- Project filter: several repos (the nvim config, the backend, this app) share one planning folder
  - a task belongs to the project when it has the project's label,
    or none of the labels listed as `projects: [...]` in `backlog/config.yml` (shared)
  - a change goes with its task; a change without a task, the specs and legacy notes always show
  - on by default when `.nvimos` names a project; `a` or the pill in the Facets shows every project's tasks
  - the Facets header says "from <folder>" when the planning folder is outside the repo
  - new tasks get the project label; task numbers count every project's tasks, so they don't collide

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
  - switching to this mode (keys or the rail) puts the keyboard in the filter;
    Esc, Tab or arrow down move it to the list
- clicking an item selects it as the Active Directory;
  clicking the Active Directory once more opens the Tasks mode
- the Active Directory
  - default: the connected Neovim does `:cd` there; the backend follows the cwd,
    sends a new git snapshot and every mode reloads
  - a toggle in this view, "New Neovim per directory": picking a dir starts a new Neovim
    instance there and the app connects to it
<!-- }}} -->


## non-functional remarks

A Note on cloning or imitating Github Desktop and Linear. The author is grateful to both companies for creating those
products and their vision, of how things work, with utmost humility and gratitude.

## Performance

- a click shows its result in the next frame; the backend answer follows
  - Tasks checkboxes, status and priority: the edit applies in memory, only the edited file is parsed again
  - the reload that our own write sets off is skipped; a reload that started before an edit keeps the edit
  - Changes stage and unstage of whole files: the file moves to the other list at once;
    the status after git answers keeps it there or puts it back, and the error shows
  - hunk staging waits for git: the other hunks' line numbers shift
- UI timing instrumentation, on in debug and profile builds, off in release; `NVIMOS_TIMING=1` / `0` overrides
  - hooked where actions already pass, not in click handlers:
    every backend call (`rpc <module>.<fn>`), the state actions (`tasks.edit`, `changes.stage`, ...)
    with their phases (`/optimistic`, `/paint`, `/git`, `/saved`), and every pointer down to the next frame
  - per action: count, p50, p95, max in ms
  - written to `%APPDATA%/nvimos/ui-timing.json` every minute and on quit: the last 30 sessions and totals
  - `make timings` shows them (`WHICH=totals` or `<n>` sessions back, `FILTER=tasks`);
    `make measure` prints the timings of Tasks clicks in a 300-task repo

## App icon

_not strictly normative_

- goal: `ops.exe` should not look like any other Flutter app, nor like Neovim itself
  - drawn from what the Flutter and Neovim logos share, copying neither:
    flat slabs, pointed ends cut at 45°, green and blue
- how we got there (OpenSpec change `ops-app-icon` in `nvimos-meta`, concept pages next to its proposal)
  - four first concepts: a prompt (chevron and block cursor), two pillars joined by a diagonal,
    a diamond, a split tile; the prompt was the favourite
  - rejected: the prompt looks like a terminal, and says nothing about Ops or about a front end
  - variants of the prompt with a window frame, a task list, an "o", a cursor that is a window: not
    wanted; the chevron was the wrong thing to keep
  - kept from the logos: the pointed 45° ends, the green and the blue
  - the word "ops" drawn as letters in that style, as three tiles: `ops`, `op`, `o`
    - `ops`: strokes turn to blocks at 16 px; `op`: readable, but half a word; `o`: sturdiest
  - chosen: the single `o`
  - then: no tile, like the Neovim logo, so it blends into any taskbar; the ring grows to fill the icon
    and keeps its tall proportions
- the icon
  - one tall octagonal ring on a transparent background, the corners of the octagon are the 45° cuts
  - green on the upper left, blue on the lower right, split on the 45° line
  - a small sky-blue triangle folded into the top right corner, the nod to the Flutter bars
- files
  - source: `assets/icon/ops.svg`, only `<polygon>`
  - `make icon` (`tool/icon.ps1`) renders 16, 24, 32, 48 and 256 px into `windows/runner/resources/app_icon.ico`

## implementation details

_not strictly normative_

- `make live` logs
  - everything flutter and the app print is also written to `out/live.log` (a new file per run)
  - `out/` is ignored by git
  - read its last lines when diagnosing what the running app did
- tests
  - 11 s per test (`TEST_TIMEOUT` in the Makefile, `dart_test.yaml`); run analyze and the test files of the change after it, not the whole suite

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
