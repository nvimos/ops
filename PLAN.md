<!-- vim: set nowrap fdm=marker: -->

---

# Plan: Ops (nvimos-poc-frontend)

A Flutter desktop app for Windows. Linux, Android and Macos versions will be implemented later.

Ops works on a local repository with no editor, through `lib/local` (`RepoBackend`). The Neovim
backend (relay, `nvimos/relay`) is optional and is used for the live editor and for a checkout on
another machine or in WSL. See that repository's PLAN.md for the protocol.

## Current modes (2026-11-19)

- **Pull request** — two local branches as a review.
- **Changes** — the working tree against HEAD, with files, hunks and commit.
- **Add and Ignore** — the file-first list: add, untrack, ignore and delete.
- **Tasks** — Backlog.md and OpenSpec as the planning database.
- **Repos** — the repositories found around the current folder; start-dirs are hints.
- **Settings**, **Log**, **Help**.

`ops.exe <directory>` opens a local repository; a `host:port` argument connects to Neovim.

## Main functionality

- In the style of GitHub Desktop, present two local branches for reviewing as a pull request.
  For example, what llm-agents did overnight.
  This is the Pull request mode.

- The Changes mode shows current working tree changes against HEAD.
  In other words, local changes.

- The Tasks mode imitates the commercial app Linear, doing more or less the same thing,
  but using the markdown files of openspec and backlog.md as a database of sorts

- The Repos mode picks the Active Directory, the repo the other modes work on.

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

- Modals (the discard, merge and archive questions, the forms)
  - the title and the text of every modal are selectable, so a warning can be copied or quoted
  - a question modal is the shared `ConfirmDialog` / `confirm()` (`lib/ui/confirm_dialog.dart`):
    one drag selects across the title and the text; the buttons stay buttons
  - the form modals (`DialogFrame`) are selectable too, their fields typing and selecting as usual;
    the command palette is the exception (a list of actions, no prose)
  - the checkout modal (`lib/ui/checkout_dialog.dart`) has three buttons, not two: see the branch switcher
    in Changes
  - a new modal uses these, so the rule holds without thinking of it

- The Mouse is the main input device. All actions are mousable.
  - an interactive item shows the pointer cursor (the pointing hand) and has a tooltip saying what it
    does, including a hidden button like the sign of a diff block
  - one exception: the file rows of the file lists keep the plain cursor
  - no double clicks: a click acts on the release, never held back to see whether a second follows
    (Purrage's double click to open went; Open is in the row menu)
    - the one exception: a double click on a resizable pane's edge resets its width (a click there
      does nothing, so nothing waits)

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
|                    | wheel over the rail does the same); the rail takes the  |
|                    | focus on the new mode's item, so the keys that follow   |
|                    | start there                                             |
| `M-1` … `M-5`      | mode by its place on the rail; the rail takes the focus |
|                    | on that mode's item, as `M-]` does                      |
| `Ctrl+B`           | expand / collapse the sidebar                           |
| `Ctrl+K`           | command palette: every action and record (Tasks)        |
| `?`                | the Help mode: this key table                           |
| `Shift+P`          | the Pull request mode with the head picker focused and  |
|                    | its list of branches open (any mode, Help too; not while|
|                    | typing in a field)                                      |
| `gi` (rail focused)| the first input of the mode shown: Pull request base,   |
|                    | Changes branch switcher, Tasks and Repos filter,  |
|                    | Help search                                             |
| `b`                | show / hide the debug bar                               |
| `Ctrl+Arrow`       | jump to the pane in that direction (PR: head picker,    |
|                    | FILES, COMMITS, diff, the rail; Changes: branch         |
|                    | switcher, STAGED, CHANGES, message, diff, the rail)     |
| `Tab` / `S-Tab`    | next / previous stop, in visual order (left column top  |
|                    | to bottom, then the right), wrapping round, as in a     |
|                    | Windows or HTML page. PR: base, head, files, commits,   |
|                    | diff. Changes: branch switcher, STAGED, CHANGES, commit |
|                    | message, diff.                                          |
|                    | Tasks and Repos: filter, list. The mode rail is one     |
|                    | stop in front of the first (not each mode in it)        |
| `/`                | filter the list (Tasks, Repos)                          |
| `.`                | widen or narrow the detail panel (Tasks)                |
| `Shift`+wheel      | over a list: the cursor moves Settings' wheel step (5 rows by default) |
| middle click       | over a list: the wheel steps the cursor one row (like Up / Down) or scrolls |
| back button        | the previous place: a task link, a review, a mode switch, a markdown link |
| forward button     | redo the jump back undid (a markdown link in the preview) |
| `Esc`              | leave the filter, close a panel, undo a narrowing       |

Any list (files, commits, branches, dirs, tasks)

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `j` / `k`, `Down` / `Up` | next / previous item; in a diff, scroll 3 lines   |
| `S-Up` / `S-Down`, `K` / `J` | in a diff, scroll 10 lines                     |
| `{` / `}` (Shift+[ / Shift+]) | three items up / down in a list (PR, Changes, |
|                    | Tasks, Repos); no hop to another pane                   |
| `h` / `l`, `Left` / `Right` | from a list to the diff / back (PR, Changes)    |
| `Down` past the last item | the pane visually below the list; `Up` past the    |
|                    | first item: the pane above (PR: head picker, FILES,     |
|                    | COMMITS; Changes: branch switcher, STAGED, CHANGES,    |
|                    | commit message)                                         |
| `gg` / `G`         | first / last item                                       |
| `Ctrl+D` / `Ctrl+U`| half a page down / up                                   |
| `Enter`            | open or pick the item                                   |
| `zo` / `zc`        | unfold / fold the selected file's folder (PR files)     |
| `zR` / `zM`        | expand / collapse all folders                           |
| `o`                | open the item in Neovim (not in a local session)       |

Pull request

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `i`, `gi` / `2gi`  | focus the base picker / the head picker (go input)      |
| `gs`               | swap base and head                                      |
| `[f` / `]f`        | previous / next file                                    |
| `]c` / `[c`        | next / previous hunk                                    |
| `v`                | unified / side-by-side (also in Changes)                |
| `Z`                | next view: unified, split, merge (also in Changes)      |
| `zw`               | toggle line wrapping                                    |
| `zh`               | toggle hunk headers                                     |
| `Enter` on a commit| narrow to that commit; `Esc` returns to the full range  |

Changes

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `C` (Shift+C)      | the branch switcher: Changes mode, field focused, list  |
|                    | open (any mode, Help too; not while typing in a field)  |
| `gi`               | focus the branch input, list closed (go input), in Changes |
| `]c` / `[c`        | next / previous hunk; the keys below then act on it     |
| `-`                | stage or unstage the current hunk, or the file          |
| `Space` / `u`      | stage / unstage the current hunk, or the file           |
| `X`                | discard (asks first)                                    |
| `cc`               | focus the commit message                                |
| `Ctrl+Enter`       | commit (in the message field); `Esc` back to the files  |

Tasks

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `c`                | new task (lowercase only: Shift+C is the branch switcher) |
| `t`                | cycle the status                                        |
| `p`                | cycle the priority                                      |
| `A`                | this project / all projects (shared planning folder)    |
| Ctrl+click a file  | open it in a new nvim-qt (detail panel)                 |
| `Esc`              | close the detail panel                                  |

Add and Ignore

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `t` / `u`          | add (stage) / untrack the highlighted files             |
| `i`                | ignore: choose the scope, the rule and the ignore file  |
| `I`                | ignore at once: a plain rule in the project `.gitignore` |
| `x`, `Delete`      | delete the highlighted files: the trash or for good, as Settings says (a question only if Settings asks) |
| `p` / `v`          | the one side pane: the ignore rules / the preview of the files (the same key again hides it; the view is remembered) |
| `T`                | Add and Ignore: all files, every tracked file too in a Tracked section (again: only the changed and untracked; remembered) |
| `Space`            | highlight / un-highlight the cursor row                 |
| `Shift+Up/Down`    | extend the highlight                                    |
| `Ctrl+A`           | highlight every row                                     |
| `r`                | reload the list                                         |
| `gi`, `/`          | focus the filter field                                  |
| `1 2 3` / `f x d`  | Ignore dialog: scope this file / extension / folder     |
| `j` / `k`          | Ignore dialog: the file the rule goes into              |
| `Enter` / `Esc`    | Ignore dialog: write the rule / close without writing   |
| `Tab`              | Ignore panes: the `.gitignore` list, then the lines     |
| `j` / `k`          | Ignore panes: pick a file / move the line cursor        |
| `h` / `l`          | Ignore panes: between the file list and the lines       |
| `Ctrl+Arrow`       | Ignore panes: jump between the panes                    |
| `Enter`            | Ignore panes: open the file, or the line, in the editor |
| `Delete`           | Ignore panes: delete the line (Undo in the notice)      |
| `Shift+wheel`      | Ignore panes: scroll the lines                          |

Repos

| Key                | Action                                                  |
|--------------------|---------------------------------------------------------|
| `Enter`            | make the dir the Active Directory                       |
| `n`                | toggle "New Neovim per directory"                       |
| `gi`               | focus the filter field (go input)                       |

Back

- The mouse's back button (X1) goes to the previous place, as in a browser. A jump records where
  the user was; the button pops one place at a time and does nothing when there is none.
- The forward button (X2) redoes what back undid, for jumps that say how to show where they went
  (a markdown link in the preview); the others are back-only. A new jump drops the forward trail.
- A place is a restore, not a route: the modes stay alive, so going back shows the right mode with
  the selection, detail panel and scroll it had.
- What records a place:
  - a task link: a `TASK-n` in a description, a note or a check, a dependency chip, the task under
    a change or spec. Back reopens the task the link came from (its detail stays open)
  - a review: opening a task's branch in Pull request. Back returns to Tasks with that task selected
  - opening a project (the Active Directory's first mode)
  - the automatic open on connect counts as opening a project: back returns to the start mode
    (Pull request). Kept deliberately; the proposal in `nvimos-meta` has the longer argument
  - a mode switch (a rail click, Alt+1..9): back returns to the mode that was shown
  - not a step (Alt+[ / Alt+], the wheel over the rail): stepping through four modes is one walk,
    not four places to go back through
- A restore may show a mode that is hidden now: hiding means "off the rail", not "cannot be shown";
  the place the user came from wins. A deliberate choice, not an oversight.
- `ui/nav_history.dart`: `NavHistory` holds up to 50 `NavPlace`s (a label and a `show` restore;
  `push(from, to:)` adds the destination that forward shows);
  `NavScope` hands it to every view. The shell owns it, listens for the back button at the root, and
  every jump records once, through `_setMode` (`_review` records the review as one place).
- A view that adds another kind of jump records a `NavPlace` with the state it leaves behind; the
  button needs no per-view handling.

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
  - the snackbar disappears after a few seconds, and its text is not selectable
  - it is dark like the rest of the app (the theme's surface color, a border, rounded corners) and has
    an X that closes it; it floats above the status bar and the debug bar, not over them
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
| Platform    | native Windows app; Flutter in `C:/tools/flutter`, Visual Studio 2022 C++ tools          |
| Connection  | TCP 127.0.0.1:6666 (`nvim --listen` or `:NvimosServe`); Dart can't open named pipes |
| Git         | the app runs no git itself; everything goes through the backend's `git.*`          |
| Editing     | Primarily in Neovim if it's open as a non-headless instance |
| Reference   | Purrage (`C:/Users/jazzo/ws/Purrage`) is the app Ops ports Add and Ignore and Repos from: its views, its `Prefs` and its `PLAN.md` are the reference when the two disagree about those modes |

### Porting Purrage (2026-11-19)

_not strictly normative_ — what the port settled, so it is not decided again by accident.

- The two ported modes keep Purrage's look where the user asked for it, and the app's own look
  elsewhere: folder/name columns and the folder amber from Purrage; the app's type scale, tints and
  icons
- no hover-only row buttons in either mode: Add and Ignore's buttons are always there, Repos has
  none, and every row action lives in the right-click menu (`HoverRow.onContextMenu` → `showMenu`,
  32 px items with a tooltip each)
  - exception, by the user (2026-11-19): the lines of the Ignore panes keep their hover buttons
    (Dirname, Delete) and also get a right-click menu (`ops-ignore-pane`)
- hover is input-modality-aware (Zed's GPUI rule): a key press suppresses the hover look, and the
  hover-only controls, until the pointer moves or a button goes down; a row scrolled under a resting
  mouse must not light up
- the side pane is one view at a time, remembered, with a remembered width — two independent toggles
  (rules *and* preview open at once) were tried and dropped
- Add and Ignore's list steps with the wheel like every list, as in Purrage: Shift + wheel moves
  Settings' `wheelStep` (5 rows), the plain wheel the small move (a scroll, or one row in the wheel
  mode)
- the Ignore dialog writes only inside the repository: the folder's `.gitignore` (for a folder row,
  one inside it, whose rule is `*`), the project `.gitignore`, and `.git/info/exclude`
  - the global ignore file is real git (`core.excludesFile`) but is not offered: on this machine it
    is a `.txt` outside the repository, and the user does not want the dialog writing it
  - "root" means the repository root everywhere in the code and paths, but the dialog says *project*
    for the rule file at that root (`IgnoreTargetKind.projectGitignore`)
- Settings: Purrage's eight settings all exist here, and the delete pair (trash or for good, and
  whether to ask) is Purrage's default: the trash, and no question
- what the local backend lists: `git status --porcelain --untracked-files=all`, so untracked files
  come one by one and a folder row only arrives from the Neovim backend
  - a test repository with an empty `src/gen/` shows `?? src/` (git collapses it); to get
    `?? src/gen/` a test tracks a file in `src/` first

## Architecture

This section describes where the code lives and what the responsibilities of the different directories are

Everything is under `lib/`; `main.dart` reads the address and starts the app.

- `rpc/`
  - `client.dart`: msgpack-RPC client over a TCP socket
    - requests with ids, responses, notifications as a stream
    - `NvimError` for errors Neovim returns (full message and a `short` form)
  - `msgpack.dart`: its own msgpack encoder and streaming decoder, no package
  - `stats.dart`: counts of the requests sent, how many wait for an answer, the answer times and
    the slowest requests (the debug bar's network monitor reads them)
  - `call_origin.dart`: what a request is and which app functions asked, from the call stack

- `backend/`
  - `backend.dart`: typed wrapper around the plugin, one RPC connection
    - checks the backend API version on connect
    - `attach`, `getText`, `open`, `show`
    - `git.*`: branches, log, diff, status, stage/unstage/discard (file and hunk), checkout, commit
    - `gitignore.*`: load the panes, untracked discovery, read, append, replace, insert, create
    - `files.*`: list, read, set lines, move, create, run a CLI
    - `jobs.*`: start and cancel
    - turns `nvimos` notifications into typed events, checks `seq` per domain, resyncs on a gap
  - `models.dart`: typed views of the plugin's maps (cursor, branches, commits, diffs, status,
    jobs, `IgnoreFileRef`, `IgnoreSnapshot`, `IgnoreAppend`)

- `local/`
  - `repo.dart`, `git_repo.dart`, `local_backend.dart`: the local backend's git and file seams;
    `LocalBackend` implements the ignore-file API by translating repo-relative refs under its root
    and delegating to `Repo`; `Repo` keeps the file reads/writes and `git ls-files` discovery
  - `ignore_rules.dart`, `ignore_edits.dart`: pure ignore-rule building and line logic (Dirname,
    Flip, the line a write landed on, the rows a write moved), unit-tested on their own
  - `hidden_write.dart`: writes a dot file that Windows keeps hidden; `trash.dart` sends files to
    the OS trash; `files.dart` is the local Tasks-mode file seam

- `state/`: `ChangeNotifier`s, no framework
  - `session.dart`: the connection, Start Neovim, and the live state every view shares:
    current window and cursor, repo info, jobs, git change hints
  - `pr.dart`: Pull request state: branches, base and head, commits, the diff
  - `changes.dart`: Changes state: working tree status, the selected file's diff, actions
  - `nvim_launcher.dart`: finds the backend checkout and starts Neovim in its own console
  - `diff_prefs.dart`: the diff layout, wrapping, hunk headers and scroll steps, shared by Pull request
    and Changes; wrapping and hunk headers are kept between runs, the layout is not
  - `prefs.dart`: small per-user settings in `%APPDATA%/nvimos/state.json` (last-seen times, branch
    links, true / false view choices, and everything the Settings mode keeps: the editor command, the
    terminal, the folder opener, the crawl depth, the wheel step, delete to the trash and its
    question, the side pane's view and width)
  - `settings.dart`: the Settings mode's state: detection of editors and terminals, the choices above,
    the Test button
  - `commit_template.dart`: git's commented instructions and file list for the commit message modal
  - `add_ignore.dart`, `ignore_choice.dart`, `ignore_pane.dart`: the Add and Ignore mode over the
    shared status: its rows, the Ignore dialog's choice and the Ignore panes
  - `dirs.dart`: Repos state: the hints, the crawl, the filter, the Active Directory
  - `list_pair.dart`: the sizes, folding and dominant list of two lists in one column
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
  - `browser.dart`: what the list shows: the view, the filter, the grouping and the sort
  - `milestones.dart`: which milestone holds a change
  - `auto_status.dart`: the status a task moves to when its last box is ticked

- `timing/ui_timing.dart`: UI timing instrumentation (see Performance)

- `ui/`
  - `shell.dart`: the window, mode rail, status bar
  - `connect.dart`, `pr_view.dart`, `changes_view.dart`, `tasks/`: the views below (aka Modes)
  - `diff_view.dart`, `file_tree.dart`, `widgets.dart`, `theme.dart`: shared pieces; `HoverRow`
    declares its pointer handlers and assembles its content and decoration from named pieces
  - `nav_history.dart`: the back stack (`NavHistory`, `NavScope`) behind the mouse's back button
  - `syntax.dart`: syntax colors of the diff's code (highlight.js through the `re_highlight` package)
  - `confirm_dialog.dart`, `checkout_dialog.dart`, `commit_message_dialog.dart`, `error_view.dart`:
    the question modals, the large commit message modal, and the error pane, snackbars and the Done
    note
  - `list_pair_view.dart`: two lists in one column (STAGED over CHANGES, FILES over COMMITS)
  - `dirs_view.dart`: the Repos mode (was Directories)
  - `add_ignore_view.dart`: the Add and Ignore mode, the whole-file triage list
  - `path_cells.dart`: the two columns of a path row, `PathFolder` and `PathName`
  - `ignore_dialog.dart`: the Ignore dialog of Add and Ignore (Purrage's), over `state/ignore_choice.dart`
  - `side_pane.dart`: the right-hand pane of Add and Ignore: its view (`SideView`), a draggable left
    edge and the width the caller remembers
  - `settings_view.dart`: the Settings mode (see below)
  - `nvim_logo.dart`: Neovim's mark drawn in code, for the status bar's backend indicator
  - `input_modality.dart`: which device (pointer or keyboard) drove the UI last; hover follows it
  - `nav_keys.dart`: the one mapping of arrows, hjkl and WASD to directions
  - `key_sequence.dart`: two-key commands with counts (`gg`, `]f`, `2gi`)
  - `reveal.dart`: keeps a list's selected row in view from the real render positions
  - `resizable_pane.dart`: a left pane the user drags wider or narrower
  - `wheel_mode.dart`: the mouse wheel over a list: scroll, or step through items (middle click)
  - `debug_bar.dart`: the debug bar and the role names of focused elements
  - `network_dialog.dart`: the modal with the slowest requests, opened from the debug bar
  - `mode_rail.dart`, `help_view.dart`, `status_bar.dart`: the rail, the Help mode, the status bar

- `test/`: unit tests per state and parser; `test/support/nvim.dart` runs a headless Neovim
  with the backend for the RPC and backend tests; the ignore backend contract runs against
  `LocalBackend` and a fake remote backend, and the relay's `nvimos.gitignore` has its own Lua tests

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
- the window is at least 468 px wide (rail expanded 180 + divider + the narrowest pane 280 + its
  7 px edge), so the 280 px panes never overflow; `windows/runner/win32_window.cpp`
  (`WM_GETMINMAXINFO`)
- Pull request and Changes have the left pane (resizable), the main pane and, while reviewing, the
  review panel; Changes' left pane holds Staged, Changed and the commit message instead
- Tasks, Repos and Help fill the mode area with one pane
- the bug button at the right end of the status bar shows and hides the debug bar
- the status bar shows the backend in front of the connection dot
  - a little desktop for the local backend, Neovim's mark for Neovim; faint while not connected
  - the tooltip reads "Backend is local" or "Backend is nvim"
<!-- }}} -->

- Search and filter fields (Tasks, Repos, branch pickers, command palette, Help) have an x at
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
  - the local backend is the default (2026-11-19): with no argument and no `NVIMOS_ADDR`, the app
    opens the last folder it opened locally that still exists, else the working directory, without
    Neovim; it never starts a Neovim on its own
  - an address as the first argument, or `NVIMOS_ADDR`, connects to that Neovim instead
  - an existing directory as the first argument opens that folder locally; the project then opens
    in the first mode with something to do, as clicking the Active Directory once more does in Repos
  - a folder that is not a repository ends here, with the error, the recents and the address field
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
      `%LOCALAPPDATA%\nvim\nvim-qt.qss` as `-stylesheet` when it exists; nvim gets the rest after `--`
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

### Style and theme

The look is Linear's calm and density with GitHub Desktop's left pane and diff, in one dark theme.
No other part of this plan says anything about it: the first part writes down what the code does,
the second what there is to decide.

#### What is

_not strictly normative_

<!-- {{{ style now -->
- One theme, dark only
  - `buildTheme()` in `ui/theme.dart` is `ThemeData.dark(useMaterial3: true)` with the colours below
    laid over it; there is no light theme, no switch and no following of the OS
  - `MaterialApp` sets no `themeMode`
  - the window is flat: surfaces are told apart by colour and a 1 px border, there are no
    shadows (the one exception is the branch picker's popup, elevation 6)

- Colours (`C` in `ui/theme.dart`)
  - `bg` `#0F1117`: the window behind everything (Scaffold), the text on a filled pill and on a
    primary button
  - `surface` `#16181F`: the rail, status bar, detail panel, dialogs, requirement cards, code boxes
  - `surface2` `#1C1F28`: the selected row and the keyboard cursor, the debug bar, hunk headers,
    input fields, popups and tooltips, inline code and code blocks
  - `hover` `#232733`: the row under the mouse
  - `border` `#262A36`: every divider and outline, the scrollbar thumb, the empty part of a progress bar
  - `text` `#E6E8EC`; `muted` `#8B90A0` (secondary text, icons at rest); `faint` `#5C6170`
    (line numbers, disabled, ids, "not connected")
  - `accent` `#6C8CFF`, the one strong colour: the selected mode's bar, the focus border of a field,
    the primary button, checked boxes, links, key labels in Help, the active list's title, Done
  - status colours: `green` `#4CC38A` (added, connected, additions), `red` `#A02A2F` (deleted,
    errors, danger, between Firebrick and Maroon), `yellow` `#E6B450` (modified, in progress, connecting, the debug bar's text),
    `purple` `#A78BFA` (renamed, needs test)
  - `found` `#66FFB84D` (ARGB), a translucent amber: the background of search matches
  - `folder` `#E8C46B`: a directory's base name, Windows Explorer's folder amber muted for the dark
    sheet (Repos, Add and Ignore), with its trailing slash
  - `current` `#266C8CFF` (ARGB), the accent at 15 %: the active row's tint (Repos: the Active
    Directory)
  - the file list's change counts (Changes, Pull request): `+N` and `−N` in two columns each, the
    sign and the number as separate items. The number has the plain colour (`addSign` `#8FD3A8` for
    additions, `red` for deletions); the sign is 40% that colour over 60% the background `bg`. A
    file without additions (or deletions) keeps its columns empty, so the counts line up down the list
  - the diff has four colours of its own, see "The diff"
  - translucent accent shows "on" and "current": 7 % on a hovered diff line, 15 % behind a toggled
    icon, 18 % behind the current hunk header; a pill's tint is its colour at 14 %

- Type
  - UI font Segoe UI, set through the text theme; code and ids Consolas (`mono`); no font is
    bundled
  - styles `T`: `title` 14 semibold, `body` 13, `small` 12 muted, `tiny` 11 muted, `section` 11
    muted semibold with 0.6 letter spacing, `code` 12.5 Consolas with line height 1.35
  - `body` is the text of rows, menus and dialogs; `tiny` that of the status bar, counts and hints
  - sizes outside the scale: the task title in the detail panel 19 semibold, "Connect to Neovim"
    18, the dialogs' text fields 15 and 16, buttons 12.5, link buttons and file counts 12, the
    debug bar 11 Consolas with line height 1.3, ids in rows 11 or 12 Consolas

- Sizes and spacing that recur
  - density: dense, as in Linear: 11 to 13 px text, 13 to 16 px icons, rows 29 to 44 px
  - pane header 40 px (`PaneHeader`: 12 px sides, 1 px bottom border, title in `T.title`);
    the Tasks toolbar is 44 px
  - status bar 24 px, 10 px sides, 1 px top border; debug bar three lines of 11 px text plus 14 px
  - mode rail 48 px collapsed and 180 expanded; the width snaps at once, the labels fade in over
    90 ms; entries 44 px high; icons 20 px
  - view bar (Pull request, Changes) 34 px, 12 px sides, 1 px bottom border; buttons 26 px, icons 15
  - list rows: `HoverRow` pads 12 on the sides and 6 above and below; file rows 5 above and below,
    folder rows 6 and 3; Tasks rows are exactly 36 px (`TaskRows.rowHeight`, 14 px sides); the
    palette's rows 34 px; menu items 32 px
  - Tasks: the facets column is 220 px wide; the detail panel slides in from the right in 180 ms
    (ease-out cubic) and has a 1 px left border that turns accent while the keys act on it
  - dividers are 1 px in `border`; the resizable left pane's drag edge is 7 px wide with that line
    in the middle and the resize cursor
  - radii: 1 and 2 (priority bars, progress bars), 3 (inline code), 4 (tooltips, icon toggles, code
    blocks, hovered check rows), 5 (buttons, link chips, the project square, the branch popup), 6
    (cards, code boxes), 8 (task dialogs, the clear x), 10 (pills)
  - icons are Material icons (`Icons.*`), outlined where there is a choice, mostly 14 or 15 px in
    rows; the status ring and the priority bars of Tasks are drawn (a ring filled 0, 50 or 75 %, a
    check or a cross for Done and Dropped)
  - gaps between inline items are 4, 5, 6, 8 or 10 px; there is no named scale

- Components
  - buttons (`SmallButton`): 28 px high, 10 px sides, radius 5, a 1 px border, text 12.5, an
    optional 14 px icon
    - plain: `surface2` with a `border` outline and `text`
    - primary: an `accent` fill with `bg` text
    - danger: the plain button with red text, never filled
    - disabled: `surface` with `faint` text
    - `autofocus` gives a dialog's safe button the keyboard
  - link buttons (`LinkButton`): 12 px accent text, 4 / 2 px padding, no underline; a few plain
    `TextButton`s (All commits, Undo) and `IconButton`s keep Material's default look
  - icon toggles: a 14 px icon in a box of radius 4; on is accent on 15 % accent, off is muted
  - pills (`Pill`): 11 px, 6 / 1 px padding, radius 10; tinted (the colour on its colour at 14 %)
    or filled (`bg` text on the colour); labels use the muted tint, the requirement count the purple one
  - checkboxes are icons, not `Checkbox` widgets: the stage box is Material's check box, 16 px,
    accent when checked and muted when not; the task check marks are 17 px: open muted, `x` accent
    filled, `.` accent outline with a dot, `~` yellow, `n` faint
  - section headers: `T.section` titles in the Tasks facets (14 px sides, 16 above, 6 below) and
    above lists; the active list's title is accent; group headers in a list are `body` semibold
    on `surface` with the status icon and a `tiny` count
  - list rows: transparent at rest, `hover` under the mouse, `surface2` when selected; a current row
    (the Active Directory) keeps its own tint (`C.current`) and a 3 px accent bar on its left edge,
    and the rows without the bar pass a transparent one (`HoverRow.bar`), so the content stays lined
    up; in the Tasks facets the selected row's text turns accent while that list has the keys, the
    other rows' text is a literal `#C8CBD3`
  - hover is input-modality-aware (`ui/input_modality.dart`), the rule Zed's GPUI names and browsers
    keep by deferring `:hover` while a scroll runs: a hover look belongs to the pointer, so a key
    press hides it — and the hover-only controls inside the row with it — until the pointer moves or
    a button goes down; a row that slides under a resting mouse while the keys scroll stays plain
    instead of reading as the focused one
  - right-click menus: Material popups (`showMenu`), 32 px items with a tooltip each; the row under
    the mouse is targeted first, or the whole highlight when the row is part of it (see Add and
    Ignore and Repos)
  - side panes (Add and Ignore): a 1 px line inside a 7 px drag area with the resize cursor; at least
    280 px, at most 60 % of the window, 360 px until dragged; a double click on the edge goes back to
    360; the width and the shown view are kept in `Prefs`
  - tooltips: `surface2`, radius 4, 12 px text, after 500 ms
  - snackbars: no `SnackBarTheme`, so they have Material's default look and not the app's colours;
    errors stay 6 s, the auto-status note 3 s (longer while the mouse is on it)
  - dialogs: `AlertDialog` for questions and `Dialog` (`DialogFrame`) for forms, both on `surface`;
    the forms have a 1 px border and radius 8, the questions keep Material's default shape;
    buttons right-aligned, 8 px apart, the action last; red only for what discards
  - fields: filled `surface2`, 1 px `border`, accent border while focused, 10 / 8 px padding, dense;
    the clear x is a 14 px muted icon
  - scrollbars: a 6 px thumb in `border`
  - error pane: a 16 px red icon, the short text in `title`, the trace in `code` muted
  - the rail: `surface`; the selected entry has a 2 px accent bar on its left edge and `text`
    colour, the others `muted`; the keyboard cursor paints `surface2`
  - the debug bar: `surface2` with a top border, all text 11 px yellow Consolas, three items to a column
  - cursor: the pointing hand on rows, buttons, boxes and their labels, the resize cursor on the pane
    edge; disabled items keep the default (a rule in `CLAUDE.md`)
  - focus: there is no focus ring on buttons, rows or panes; a text field gets an accent border;
    the active list's title is accent; the detail panel's left edge and the rail's cursor are the
    other signs; the debug bar names the focus when it is on
  - motion: only the rail (120 ms) and the detail panel (180 ms), plus Material's own ripples and
    snackbar slides; hover changes are instant

- The diff (`ui/diff_view.dart`)
  - code in `T.code` (Consolas 12.5), no syntax colours; tabs are shown as four spaces
  - added line `#13261C` with a `#1B3A29` gutter and a green `+`; removed line `#2A1517` with a
    `#3E1D20` gutter and a red `−`; context lines have no fill and a faint blank sign
  - the number gutters are 44 px (old and new; one in each half of side by side), numbers right-aligned
    in `faint`, then an 18 px sign column, then the text
  - the hunk header: `surface2`, `@@ −a,b +c,d @@ section` in 12 px accent Consolas; the current hunk
    gets accent at 18 %; a clickable line shows the hand and a 7 % accent veil
  - side by side: two halves split by a 1 px line; a missing half is `surface` at 50 %; a 320 px
    side panel can sit beside the diff
  - long lines scroll sideways unless wrapping is on; the scroll width is the longest line times the
    width of one character
  - the file title in the header: the status icon (15 px, status colour), the path, `+n` green and
    `−n` red at 12 px

- What is echoed from Linear, GitHub Desktop and Meld
  - from Meld (merge conflicts): the three-pane view of ours, the merged result and theirs, with a
    pick of either side for each hunk; the conflict view opens from the merge button, with no dialog
  - from Linear (Tasks): dark, quiet, one accent; dense 36 px rows with a status ring, a priority
    glyph, a mono id, label pills and small progress bars; the facets on the left and the detail
    panel that slides in on the right; small muted section titles; a command palette
  - from GitHub Desktop (Pull request, Changes): a resizable left pane with the file list (folders,
    status icons, `+n −n`) and the commits under it, the diff on the right with gutters and hunk
    headers, a stage check box at the end of a file row, the branch name as a switcher, the unified
    and side by side choice
  - departures from both: dark only; a vertical rail of modes; a key for everything, with Help and
    a debug bar; the palette is its own (not copied from either app)

- Inconsistencies and loose ends found in the code
  - literals outside `ui/theme.dart`: the facet text `#C8CBD3` (`tasks_nav.dart`); 41 inline
    `fontSize:` values (11 to 19) next to the six `T` styles; 15 inline `fontFamily: mono` styles that
    repeat `T.code` with another size (11, 12); the diff's gutter, sign and hunk sizes; dialog widths
    (420, 560, 600, 620, 680)
  - mixed spacing: row side paddings of 10, 12 and 14; icon-to-text gaps of 4, 5, 6, 8, 9 and 10 px;
    eight radii (the same kind of box is 4, 5 or 6)
  - icon sizes of 12, 13, 14, 15, 16, 17 and 20 px (14 and 15 are used about equally for the same job)
  - two code boxes: `CodeBox` (Connect: `surface`, radius 6, border) and the Tasks code block
    (`surface2`, radius 4, no border)
  - dialogs have two shapes (Material's for questions, radius 8 with a border for forms); popups
    are two as well (Material's `PopupMenuButton`, and the hand-built branch picker with elevation 6)
  - snackbars and the plain `TextButton` / `IconButton` use Material's default look, so their
    hover, focus and ripple colours come from the Material scheme, not from `C`
  - the native window title is "Ops" (`windows/runner/main.cpp`) but `MaterialApp.title` is `nvimos`
  - `yellow` has four meanings: modified, in progress, connecting, and the debug bar's text
  - no visible focus on buttons and rows, and `faint` on `bg` is weak contrast for line numbers
    and disabled text
<!-- }}} -->

#### Plan

_not yet built, not normative_

<!-- {{{ style plan -->
Decisions to make and proposals, drawn from the findings above. None of it is decided.

- One source for the look
  - `ui/theme.dart` the only place with a colour, a font size, a radius or a spacing step; a widget
    names a token and has no literal (the measures of one widget, such as a column width, may stay)
  - the sizes that have no name get one (the 19 of the task title, the code and id sizes), so the
    inline sizes go away
  - one dialog shape, one popup, one code box, one snackbar theme, and a button theme that also
    covers `TextButton` and `IconButton`
  - the native window title and `MaterialApp.title` agree

- A spacing scale
  - proposal: 2, 4, 6, 8, 12, 16, 24, with 10 and 14 retired
  - proposal: radii 4 (controls, chips), 6 (cards, dialogs) and full round for pills
  - proposal: icon sizes 14, 16, 20
  - the fixed heights stay: 40 header, 36 row, 24 status bar, 48 rail

- A light theme and a switch
  - decide whether to have a light theme at all
  - if so, a setting with Dark, Light and System; System follows the OS; kept with the other small
    settings in `prefs.dart`
  - every colour becomes a pair, which the previous point makes possible; the diff's four colours
    need a light pair too
  - open: whether the app's theme and Neovim's colour scheme are linked

- Font size
  - PLAN.md already says the font size is meant to become a setting (see "Layout of the window")
  - proposal: one scale factor over the type scale and what follows from it; the diff's code size
    could be a second one
  - lists already read their row heights from the render tree, so they cope

- Contrast and focus for keyboard use
  - the app is keyboard first, so the focus must be visible: every stop in the Tab order shows
    where it is, with the accent (an outline, or the accent bar the rail and the detail panel
    already use), and the active list's selected row reads stronger than an inactive list's
  - contrast: aim at 4.5:1 for text and 3:1 for icons and boundaries, in both themes; check `faint`
    and `border` against it
  - a colour never carries a meaning alone: the diff keeps its `+` and `−`, the statuses keep their
    icon shapes

- Syntax highlighting (a separate topic, not decided; the candidate package is `re_highlight`)
  - whatever is chosen, its theme has to read on the diff's green and red fills as well as on `bg`
  - proposal: colour the code, leave the line fill alone, and keep red and green out of the token
    palette, since they mean removed and added
  - the choice follows the theme setting

- Icons
  - proposal: stay with Material icons (they are in the framework), outlined for rest and filled for
    on, and keep the drawn status ring and priority bars, for which there is no icon
  - open: whether to move to one other set later

- Density
  - proposal: today's look is the compact density and stays the default
  - open: a comfortable density, as a larger scale factor on the spacing scale, together with the
    font size setting

- What to keep
  - from Linear: calm (one accent, flat surfaces, no shadows), dense lists, status icons, pills, the
    detail panel that slides in
  - from GitHub Desktop: the resizable left pane, the diff's gutters and line fills, the stage check
    boxes, the branch switcher
<!-- }}} -->

### Left sidebar (mode rail)

<!-- {{{ sidebar -->
- a narrow strip, 48 px wide, on the left edge of the window
- the top item is a toggle that expands and collapses the sidebar
  - expanded, each icon gets a short label beside it, so the sidebar stays narrow
  - hovering an icon or label shows a brief explanation of the mode,
    like an HTML `title` tooltip.
- one icon per mode, top to bottom (Alt+1 … Alt+9): Pull request, Changes, Add and Ignore, History, Tasks, Repos, Settings, Log, Help
  - the order is the user's: drag an icon up or down the rail; it is saved in the state file and the
    next start uses it
  - a press becomes a drag only after the pointer moved 8 px (a finger: Flutter's touch slop,
    18 px); a shorter wobble stays a click that opens the mode
  - right-click an icon to hide that mode; it leaves the rail, and Alt+1..9, Alt+[ / Alt+] and the
    wheel skip it
  - at least one mode stays visible; Settings lists the hidden modes and puts one back in the place
    it was dragged to; a **Reset the rail** button restores the default order and shows them all
  - the saved arrangement is names, not ids: at startup a name that no longer exists (a mode was
    renamed or removed) is dropped, a mode added since the save comes last, duplicates go, and a
    hidden set that would hide every mode is forgotten; the repaired state is written back
  - History and Log show a short "not built yet" note until their views arrive
- Help lists every key the app has; it works without a connection too
  - the key groups fill the pane in columns about 360 px wide, as many as the width allows; the
    groups keep their order and the columns even out in height; the table scrolls when a screen is
    too short for every group
  - a narrow pane gets fewer columns; a column never goes below 250 px, and below that the right
    edge is clipped
  - a window resize freezes the table, scales it uniformly to the new width, and reflows once
    150 ms after the last width change; descriptions are one line while resizing and wrap at rest
  - a Mouse group lists what the clicks, the wheel, the middle button, the back button and the rail
    drags do (Shift+wheel, middle click, click, right click and Ctrl+click on a checkbox,
    Ctrl+click on a task, the back button's previous place, a dragged rail icon)
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
  - nothing opens under a mode, so the rail never moves; the diff views of Pull request and Changes
    are in the view bar above their panes (see Pull request)
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
- Repos mode, a folder icon
  - its icon comes after all other mode icons, not anchored to the bottom of the rail
  - see "Repos mode" below
<!-- }}} -->

### Debug bar

<!-- {{{ debug bar -->
- for finding out where the focus goes; off at start, toggled with the bug button in the status bar
  or the `b` key (not while typing in a field, and not in Help, where `b` is search text)
- a pane above the status bar that takes its height from the mode area (not an overlay)
- three lines high, made of boxes (a border, rounded corners, a margin around each) so neighbours read
  as separate widgets: the focus box and the network monitor
- in the focus box, items stack three to a column and continue in the next column, so it never
  becomes one long line; what does not fit next to the network monitor is cut off
- each item is "Label: value" with the colons of a column on one line:
  - Focus: the focused element by its role in the interface (not its class), e.g. "Commits list",
    "Base revision field", "Mode rail", "Task detail"
  - Back: the label of the place the mouse's back button would show, or `none`; it updates as the
    stack changes
  - clicking the Focus value opens a dialog, "Focus path": the path of the focused element in the
    focus tree from the root down, each node by its label (an unlabelled node by its widget type),
    joined with ` > `; the text is selectable with the mouse
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
- the network monitor, a box at the right: the health of the conversation with Neovim, three lines,
  refreshed twice a second
  - Requests: how many were sent in the run, per second over the last 5 seconds, and how many failed
  - Waiting: how many requests wait for an answer now, the most at once, and the oldest one's wait
    (the queue; red when more than 5 wait or one has waited over 500 ms)
  - Answers: median (p50), p95 and the slowest answer time (the percentiles over the last 200 answers)
  - the numbers come from `RpcStats` (`lib/rpc/stats.dart`), which `NvimRpc` feeds on every request
  - a click on the monitor opens a modal, "Requests to Neovim": the requests waiting now and the 30
    slowest of the run, slowest first, each with
    - how long it took (or has waited), red from 500 ms
    - what it is: the Lua function (`nvimos.git.diff_file`) or the RPC method, and its first argument
      when that is text (a path, a branch)
    - which functions of the app asked, nearest first (`ChangesState._loadDiff ← _ChangesViewState._pick`),
      read from the call stack when the request is made
    - when it was sent (time since the app started) and "(failed)" for an error
  - Refresh in the modal reads the numbers again; all of it is kept in memory for this run only,
    never written anywhere
<!-- }}} -->

### Status bar

<!-- {{{ status bar -->
- appears at the bottom of the app
- Active Directory, current branch, Neovim's current file and cursor (live), connection state
- at the right end, a bug button shows and hides the debug bar (see "Debug bar")
- the status bar and the debug bar are the window's bottom bar, so snackbars slide in above them
<!-- }}} -->

### Views (Modes)

#### Pull request ("Review")

- layout
  <!-- {{{ -->
  - three columns, left to right
    - left pane, resizable by dragging its right edge (double-click: back to automatic)
      - automatic width: the narrowest that shows all its text, between 150 and 360 px
      - Base Picker
        - base defaults to the checked-out branch (main or master only when HEAD is detached),
          head to the newest other branch
      - the actions line, between the two pickers
        - the Swap button (swaps base and head) in the label column, between the "base" and
          "head" labels
        - the merge actions in line with the fields, on the same line; more can follow
        - "merge" button: head into base, a merge commit (`--no-ff`) on base, local only, nothing is pushed
          - enabled when both sides are picked, differ and the diff has files
          - no question first; base is checked out first when it is not the current branch
          - refuses unsaved buffers or uncommitted changes to tracked files, a base that is not
            a local branch, and a head with nothing new
          - a pre-flight `git merge-tree --write-tree` runs first, read only: with no conflict the merge
            runs as above; with one, nothing is merged and the conflict layout opens (see "merge conflict
            view" below); the same check runs again when the view opens, and a conflict that is gone
            merges as a plain merge with a note
          - done: a short note "Merged head into base" (or "no conflicts after all"); the lists refresh
          - base moved during a clean merge (someone committed to base meanwhile): nothing is saved,
            and Ops offers to rebase head onto the new base, then merge it
          - strong preference, decided 2026-11-15: rebase, not a second merge, so the history of
            base reads as one straight line; the user confirms the offer, it does not run by itself
        - "merge conflict view": a third diff mode beside unified and side-by-side, opened automatically
          - first version: per hunk, pick either side (modeled on Meld); a conflicted file can also be
            opened in nvim (nvim-qt, a new instance, on that file, not in diff mode)
          - the merge is finished by the commit in Changes (add marks a file resolved; the commit
            completes the merge on base)
          - open point, decided for now: the outcome is a merge on main. Concern: a mistake in the
            resolution lands on main as-is, and main may be left broken. Two alternatives to weigh later:
            1. an extra commit on the branch being merged: produce the resolution as a diff, commit it
               on head, merge that, so the resolution is reviewable on the PR
            2. produce the resolution as a diff, apply it to head, and reset base to the state it had
               before the merge started, so main is untouched until a clean result is known
          - add refuses a file that still has conflict markers (`<<<<<<<`, `=======`, `>>>>>>>` at the
            start of a line); the error names the file and the first marker line, and the file stays unresolved
          - verify step before the commit: no unmerged paths left, no conflict markers in staged files;
            tests and analysis are optional, not a gate
          - done: a short note "Merged head into base"; the lists refresh
        - "rebase" button, 8 px right of "merge": head's commits replayed on top of base, local only
          - enabled when both sides are picked and differ; no question first
          - head is checked out first when it is not the current branch; the same refusals as merge
            (unsaved buffers, uncommitted changes to tracked files), and head must be a local branch
          - a conflict is undone (`rebase --abort`) and the error names the files
          - always answers with a short note: "Rebased head onto base", or "head is already on top
            of base" when there was nothing to replay; the lists refresh
      - Head Picker
        - each picker leaves out the branch the other one has: no `main` in the head list while
          the base is `main`, and the other way round (the same on both sides is an empty diff)
        - a revision typed by hand (`HEAD~2`) is still taken, whatever the other picker has
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
  - each file has a status mark before its name, the symbols and colors oil-git.nvim draws in Oil:
    `+` added (green), `~` modified (yellow), `->` renamed (purple), `D` deleted (red), `!` conflict
    (orange), `?` untracked (blue)
  - the plain arrow cursor over file rows (a click on a file is obvious); folder rows show the pointer
  - the wheel steps the selected file after a middle click or with Shift (`FileTree.onStep`)
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
    - toggle line wrapping (`zw`)
    - toggle the hunk headers (the `#` button, `zh`)
    - both choices are kept between runs (`%APPDATA%/nvimos/state.json`) and shared by Pull request and Changes
  - switching views: a view bar above all the panes of Pull request and Changes has one button per
    view, Unified, Split (side by side) and Merge (the merge conflict view; dimmed unless a merge with
    conflicts is open); `v` toggles Unified and Split, `Z` steps Unified → Split → Merge
  - unified diff of the selected file, like GitHub's "Files changed" tab; side-by-side pairs each run
    of deletions with the run of additions after it
  - syntax colors (`ui/syntax.dart`)
    - the language comes from the file name: 21 languages, other files stay plain
    - each hunk is colored as a whole, once for its old side and once for its new side, so a comment
      or string over several lines is right; a hunk with a line over 1000 characters stays plain
    - the colors are highlight.js's ir-black theme, the closest bundled one to the Neovim
      colorscheme (lunaperche)
  - how changed lines look
    - the line numbers on the left stay neutral; only the sign and the code have the add or delete color
    - a run of changed lines of one kind is one blob: the color is soft (60 %), fades in at the top
      edge of the first line and out at the bottom edge of the last, fades in at the left edge and
      tapers off over the right part of the line, so the empty space on the right looks like the
      background
    - where a run of deletions meets a run of additions the two blend into each other at the line
      between them, with no gap showing the background
    - only the first line of a run has the `+` / `−` sign; its line numbers are in the sign's color
      (a paler green for added lines), the numbers of the lines below are neutral
  - the header of a hunk is quiet: where it is ("Lines 120–134", "Line 120", "after line 120"), how
    much it changes (`+4 −2`, in a dimmed accent color) and what it is in ("in <section>", faint),
    on a faint strip that fades to the right; the current hunk (`]c` / `[c`) is tinted and has an
    accent edge
    - the hunk headers can be hidden (`zh`): their rows then take no room, the code runs on
  - in Changes, the sign of a changed block is a hidden button: it looks like plain text, shows the
    pointer and a tooltip ("Stage hunk" / "Unstage hunk") and does what the header's button does
  <!-- }}} -->
- Click a file or hunk line: Neovim opens that line in the current buffer
  - head checked out: the working tree file
  - head not checked out: a read-only copy of the file at head (deleted lines: at the merge base)
  - the current buffer has unsaved changes: open in a new window instead


#### Changes ("WIP")

staged and unstaged files with checkboxes, the selected file's hunks with stage,
unstage and discard buttons, commit message and Commit button. Click a line: Neovim opens it.

- the branch switcher heads the left pane, in place of the branch's name
  - the same field as the base and head pickers of Pull request (`RevPicker`: a click on it opens the
    list of all branches, a click again closes it, typing filters), but it is a separate widget with its
    own state: picking here never changes the pickers there
  - the list works as an autocomplete drop-down, in all three pickers
    - Down in the field goes to the list's top item, opening the list if it is closed; Down / Up
      step through the items
    - the item the keyboard is on is highlighted; the list stays filtered on what was typed
    - Up from the first item returns to the field; Escape closes the list; Enter or Space picks the
      highlighted item; a letter in the list goes back to the field and replaces its text
  - `C` (Shift+C) from anywhere, Help included (so a capital C cannot start a search there; typing in
    a text field, Help's search too, still types it), switches to Changes, focuses the field and opens
    the list, as a click would; `gi` in Changes focuses the field without opening the list, as in Pull request
  - after a pick, a Cancel in the checkout modal or a failed checkout, the keyboard is on the Changes list
  - it only takes a listed local branch (no sha or tag); Enter or a click on a branch checks it out,
    typing alone never does (no pick after a pause, unlike the pickers)
  - uncommitted changes to tracked files would be overwritten: a modal lists those files first, before
    anything happens (untracked files stay and are not listed)
    - Cancel is the default button: Enter and Space (and Esc) leave everything as it is
    - Stash and checkout: stashes the changes (`nvimos: before switching to <branch>`), then switches;
      when the switch fails the stash is put back
    - Checkout and discard (red): throws the changes away; reached only by navigating to it or clicking it
    - unsaved buffers in Neovim always refuse the checkout
    - no changes in the way: the branch is checked out at once, without the modal
  - the backend does the work (`git.checkout(branch, how)`, `how` = `stash` or `force`)
- each file row of CHANGES has an "add" button at its right end (tooltip "Stage current file"), each
  file row of STAGED a checked box ("Unstage current file"): a click moves the file to the other
  list at once
  - the "add" button shows only while the mouse is over its row (always where there is no mouse,
    on Android and iOS); the checked box always shows; the space stays, so rows line up
  - each folder row has the same button ("Stage folder" / "Unstage folder"): a click stages
    (unstages) the files directly in that folder; files of subfolders have their own folder rows
- when STAGED has nothing left (Unstage all, the last file unstaged, a commit) and had the most-room
  flag, the flag goes to CHANGES, which unfolds
- selecting a file shows it at once, but its diff is fetched after the selection has rested 120 ms,
  with one request (not status and branches again): holding an arrow key through many files asks for
  only the last one's diff
- the commit message field has two buttons at its right end
  - an X that clears it, shown while there is text
  - a button for a large window ("Edit the message in a larger window"): a modal, about 60 % of the
    window, with the message above git's commented instructions and file lists (what `git commit`
    shows in Neovim: branch, "Changes to be committed", "Changes not staged for commit",
    "Untracked files"); "Use message" or Ctrl+Enter puts the message back without the `#` lines,
    Cancel or Esc leaves the field as it was; it does not commit
- STAGED over CHANGES behave like the Pull request files and commits: foldable headers,
  the most-room button (CHANGES have it at start), expand / collapse all folders (zR / zM)
- unified and side-by-side diffs, like the Pull request mode
  - the view bar above all the panes has a button per view: Unified, Split (side by side) and
    Merge (dimmed unless a merge with conflicts is open); `v` toggles Unified and Split, `Z` steps
    through all three
  - one choice for both modes (and the line-wrapping toggle, `zw`)
- the left pane is resizable, like in Pull request
  - drag its right edge with the mouse; double-click the edge for the automatic width
  - automatic width: the narrowest that shows all file, folder and header text and the commit
    button, between 280 and 384 px; dragging is limited to 70 % of the window
- the files are listed, and walked by the keys, in the order the tree shows them: files of the top
  folder first, then the folders, each sorted by path (not git's status order)
- panes: the branch switcher, STAGED, CHANGES, the diff (and the commit message for Tab)
  - the branch switcher is the first stop of the left column: Tab, Ctrl+Up / Ctrl+Down and Up past the
    first file reach it (the field is focused, its list stays closed), Down or Tab leave it for the
    first list, Left at the start of its text goes to the rail; Up never goes past it
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
    - the wheel mode steps one entry a notch; Shift + the wheel steps Settings' wheel step (5) in
      either mode
    - the task list does the same, stepping the current task (`WheelMode`, `ui/wheel_mode.dart`)
    - so do the file lists (Changes: STAGED and CHANGES; Pull request: FILES CHANGED) and the
      commit list: the wheel steps the selected file or commit, staying inside the list (`FileTree.onStep`)
    - Up / Down in the Facets make the next entry the current view
    - Right from the list goes to the current task's detail; there the direction keys move from
      element to element (buttons, fields, rows), not by lines; Left past the leftmost element
      goes back to the list; Tab visits the elements in order and on to the rail; Esc closes it
  - one special case for the user's layout: the key where D is on QWERTY is Right whatever letter
    it types (found by its scan code); no other key is matched by position
  - the arrow keys, h j k l and W A S D do the same (Tasks and Repos have no panes: only
    w / s there); the commands that had `s` and `a` moved: stage is Space in Changes, status is `t`
    and the project scope Shift+A in Tasks
  - the file and commit lists scroll to keep the selected row in view
  - Tab / Shift+Tab: branch switcher, STAGED, CHANGES, commit message, diff, wrapping round
  - an arrow key in the commit message steps out of it when it could not move the caret: Up on the
    first line (to the list above), Left at the start of the text (to the rail), and in an empty
    message also Right (to the diff); otherwise arrows move the cursor, letters type
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
- Changes and tasks: a change starts on its own, not from a task
  - a new change's proposal names no task; its Status line is just `Status: To Do`
  - a change can spawn tasks, and each names its change (`Change:`); the link goes from task to change
  - no task is filed first just to give a change a number
  - older changes that name a task (`Status: X (backlog TASK-n)`) still link both ways
  - the planning repo still says otherwise (`nvimos-meta`: `openspec/config.yaml`, `README.md`,
    `openspec/specs/planning/spec.md`); this rule wins
- `tasks/edits.dart`: line-level edits (status in YAML header, checkbox toggle, Status line in
  proposal) sent as `files.set_lines`; each refuses if the line changed meanwhile.
- the detail panel's text is selectable: one selection over the whole panel (title, proposal, task
  text, raw file), copied with Ctrl+C; a click in the text is not a Tab stop
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

#### Add and Ignore mode

<!-- {{{ -->
- the whole-file triage list from Purrage: one row per changed or untracked path, in sections
  (conflicts, staged, changed, untracked); Changes stays the diff and hunk mode
- rows follow Purrage's Changes list: the change's letter, the folder right-aligned in monospace
  `muted` with its trailing slash, the row's buttons, then the base name
  - a folder too long for its column (a wide side pane) loses its start, not its end:
    `…ui/widgets/`, so the part next to the base name stays (`fitTail`, `path_cells.dart`)
  - the buttons sit in a fixed 63 px slot and are always there — add (`+`) or untrack (`−`), then the
    eye that ignores the row (`I`): the literal path into the project `.gitignore`, and for a tracked
    row `git rm --cached` as well, since a rule alone does not untrack (the file stays on disk; the
    row leaves the list as a staged deletion until that commit) — so the name column is the same on
    every row; there are no hover-only buttons
  - a directory's base name is amber (`C.folder`) and keeps its trailing slash, so it reads as a
    folder
  - a section heading reads `Staged (3)` in `T.section`, at the bottom of its 28 px strip
- a right click opens the row's menu, after targeting that row (or the highlight, when the row is in
  it), as in Purrage: `Open` (the file in the editor Settings names), `Ignore…` (the dialog), `Delete`
  (`x`; to the trash or for good, as Settings says); every row button and menu item has a tooltip and
  the pointer
- delete follows Settings: the trash by default, for good when that is chosen, and the question
  first only when Settings asks for one (`confirmDelete`, off by default) — the dialog's title and
  wording follow the choice (`Move to the trash?` / `Delete for good?`)
- all files (2026-11-23): a button in the list's header, left of the preview, ignore panes and
  reload buttons, and `T`, list every file git tracks too, so the mode doubles as a quick file
  browser beside the preview. This stretches the mode beyond git and ignore, on purpose
  - the clean tracked files come last, in a **Tracked** section; a changed file stays in its own
    section and is not listed twice; their letter is a muted `·`
  - a tracked row has untrack (`−`) and the eye (ignore and untrack), Open and Delete in the menu;
    no add
  - the paths come from `git ls-files`, read when it goes on and after each status refresh, and
    replaced only when they changed; off, nothing runs. The button is lit while it is on; the
    choice is remembered (`addIgnoreAllFiles`)
- the right-hand pane is Purrage's: one view at a time (`p` the ignore panes, `v` the preview), open
  at start on the view last used, remembered in `Prefs` (`sideView`)
  - a visible switch above it picks the ignore panes or the preview; the same key again hides the
    pane, the other key switches it; the close button on the switch hides it
  - its left edge drags (7 px, the resize cursor) between 280 px and 60 % of the window; 360 px
    until dragged, a double click on the edge goes back to it, and the width is remembered
    (`sidePaneWidth`)
  - under 600 px of window width it starts hidden; `p` or the switch still opens it for the session,
    and a later resize does not undo that choice
  - the preview reads the highlighted files once per change of the highlight, and only while it is
    the shown view (`renderPdf` from Settings decides whether PDF pages are drawn)
  - a markdown file (`.md`, `.markdown`) is drawn rendered: headings, lists, tables, code, quotes;
    the text stays selectable. A **Rendered / Text** switch in the pane's header (only while a
    markdown file is shown) flips to the numbered lines; the choice is remembered
    (`previewRendered`). Both views are built at load, so the switch reads nothing
  - links in rendered markdown work like a small browser: another markdown file shows in the
    preview (the mouse's back and forward buttons walk the trail), a web address goes to the
    system's browser, any other local file opens like the Open button; a picture from the repo is
    drawn, a web picture shows its alt text
  - rendering is a build option, on by default: `make configure markdown=off` builds without it
    (`packages/ops_markdown_off`), and the preview shows markdown as text without the switch
  - an HTML file (`.html`, `.htm`) gets the sentence with **Open** (the browser shows the real
    page) and, under it, the page drawn without a browser: tags and basic CSS, no JavaScript, no web
    requests (a web picture shows its alt text). The same switch, the same links (an HTML page opens
    in the preview, an in-page anchor does nothing). `make configure html=off` builds without it
    (`packages/ops_html_off`, `flutter_widget_from_html_core` in `ops_html_on`)
  - neither view reads while the switch hides it: they mark themselves stale and load when shown
- both modes sit on one status store and one action queue (`Session.store`, `Session.actions`), so
  an action in one shows in the other; each keeps only its cursor, selection and filter
- plain, Ctrl and Shift selection with the mouse; Shift+arrows, Space and Ctrl+A with the keys
- the list steps with Shift + the wheel by Settings' wheel step (`wheelStep`, 5 rows by default),
  and with the wheel after a middle click by one row, like every other list; the wheel scrolls it
  otherwise
- the Ignore dialog (`i`, the row menu's `Ignore…`) is Purrage's dialog
  - it opens for every highlighted row, tracked ones too: ignoring a tracked file writes the rule
    and nothing else (untracking it is `u`)
  - Scope: chips *this file*, *this extension*, *this folder* (`1 2 3` or `f x d`)
  - Where: the folder's `.gitignore` (for a folder row, one inside it, whose rule `*` ignores what is
    below it), the project `.gitignore`, or `.git/info/exclude`, each with its path and a check while
    chosen (`j` / `k`); a target whose file is not there yet says so and is created by the write; the
    default is the narrowest `.gitignore` that exists, else the project one
  - the targets come from the backend's pane load plus its untracked discovery, so an existing
    untracked nested `.gitignore` is not called missing
  - the preview: `3 files → 1 rule`, each rule once, and the rows the scope makes no rule for
  - Enter writes, Esc cancels; the Ignore button is off while nothing would be written
  - after a write the ignore panes select that file and centre the first new rule, without an
    animated scroll; a duplicate selects the file and does not scroll
- the Ignore panes (`p`) are Purrage's two panes, without the match lookup
  - left: every `.gitignore` of the project, the root one as `project .gitignore`, named by its
    folder otherwise; 35 % of the pane, at least 80 px
  - right: every line of the selected file as it is — rules, comments and blank lines, no numbers;
    one line each, cut with an ellipsis, at one fixed height from the text style
  - the list starts on the project file when it exists, else the first file, keeps the user's pick
    for the session, and never follows the cursor row; the files that govern the cursor row's folder
    are marked (a trial), without moving the selection
  - a line cursor: `j` / `k` move it, `Delete` deletes the line, `Enter` opens the file at it; the
    list and the lines are two Tab stops, `l` / `h` and Ctrl+arrow move between the panes
  - a line's right-click menu: Delete, Dirname, Flip, Open; the hover buttons stay (Dirname, Delete),
    the one exception to "no hover-only row buttons"
  - Dirname takes a positive rule one folder up (refusals: "dirname only works on positive rules",
    "please edit negation rules manually", "please edit wildcard rules manually", "no folder above
    this rule"), removes the line when the parent rule is already there; Flip toggles the leading
    `!` ("flip only works on rules")
  - an edit acts at once; the notice says what changed and has Undo, one at a time; a removed line
    comes back through `insertIgnoreLine`, and Undo refuses when the file changed meanwhile
  - the notice also counts the rows that left or came back ("2 files now ignored", "1 file back in
    the list"), from the status before and after, without an extra git call
  - Open in editor opens the file (or the line) through `EditorSession`; New here creates a
    `.gitignore` in the cursor row's folder through the backend (inside a directory row, at the root
    for a root file)
  - the files are read once on open (one `loadIgnorePanes`, then `untrackedIgnoreFiles`); again only
    when the status lists a changed `.gitignore` path or after the app's own write; picking another
    file reads only that file; a cursor move reads nothing
  - a project without any `.gitignore` says "No .gitignore files" and offers Create project
    `.gitignore`
- ignore-file I/O goes through `RepoBackend` with repo-relative names (`IgnoreFileRef`), so a
  Neovim in a VM or over SSH works; no local absolute path, and no `ensureRepo()` on that path
- the global ignore file (`core.excludesFile`, `~/.config/git/ignore`) is not offered anywhere: git
  reads it, but this app does not write rules into a file outside the repository
<!-- }}} -->

#### Settings mode

<!-- {{{ -->
- what Purrage's Settings had, plus what this app added; every choice is saved at once in
  `%APPDATA%/nvimos/state.json` and applies without a restart, since it is read where it is used
- EDITOR: the editors found on this machine in detection order
  - a click on a row makes that editor the command (the row in use stays unclickable, as clicking it
    would change nothing); a saved command leads, marked as the one in use
  - the field takes a command with `{file}` and `{line}`; Save keeps it, "Use the detected one"
    clears it so the first detected editor leads again
  - Test opens `PLAN.md` — the open repository's, else the app's — in the editor in use, and a
    failure shows as the usual action notice
  - the header's refresh looks for editors and terminals again
- TERMINAL: the terminal a repository's menu starts; the first found until one is picked
- FOLDERS: what a repository folder opens in: the file manager (default) or the editor
- DELETE: `To the trash` (default) or `For good` — what the Delete action of Add and Ignore does
- CONFIRM: `Ask first` or `At once` (default, as in Purrage); the question names what goes and
  follows the trash choice
- WHEEL: rows one Shift + wheel notch moves a list
  - 2 to 1000, 5 until chosen; a number out of the range is said under the field and not saved
- PREVIEW: whether the Add and Ignore preview draws a PDF's first pages (off: a note and an Open
  button)
- CRAWL: how many levels below its start folder the crawl looks for repositories, 1 to 12 (default 5,
  see Repos); it applies to the next crawl
- MODES: the modes hidden from the rail, in rail order; a click on a row puts that mode back in the
  place it was dragged to. The rail's order itself is changed by dragging its icons (see the rail)
  - **Reset the rail** restores the default order and shows every mode
<!-- }}} -->

#### Repos mode (was Directories)

<!-- {{{ -->
- works only while connected; disconnected, the view says so
- rows follow Purrage's Directories list: the folder icon, the folder right-aligned in monospace
  `muted` with its trailing slash, then the base name
  - a name is amber (`C.folder`); a stale hint's is faint
  - the Active Directory keeps the amber name and is marked by a 3 px accent bar, the accent tint
    (`C.current`) and its "Active Directory" label in the accent
  - the label sits in a fixed slot as wide as the longest one ("no longer a repository"), so the
    folder's right edge and the name's left edge line up on every row
  - a row has no buttons: everything is in its right-click menu
- a right click opens the row's menu, as in Purrage: `Manage` (make it the Active Directory and open
  the project), `Open` (the folder in the editor or the file manager, as Settings says), `Terminal`,
  and `Crawl from here`; a stale hint offers only `Remove`
- lists the start dirs of the genja-startdirs plugin,
  in the same order as its Telescope picker (`:Telescope mydirs`, by frecency)
  - without genja-startdirs: the dirs of Neovim's recent files (`v:oldfiles`), most recent first
  - the backend provides the list, the app reads no files itself
- picking a dir counts as a use for genja-startdirs (the backend calls its `touch`, like its picker)
  - without genja-startdirs there is nothing to count
- the list is filterable;
  when the filter leaves one item, it is selected and becomes the Active Directory.
  - switching to this mode (keys or the rail) puts the keyboard in the filter;
    Esc, Tab or arrow down move it to the list
- clicking an item selects it as the Active Directory;
  clicking the Active Directory once more opens the project, in the first mode with something to do
  - Pull request when there is a local branch besides the default one (`main`, else `master`):
    something to review
  - else Changes when the checkout has uncommitted changes
  - else Tasks, even when there are no tasks
  - when git can't tell (not a repo), Tasks
- the Active Directory
  - default: the connected Neovim does `:cd` there; the backend follows the cwd,
    sends a new git snapshot and every mode reloads
  - a toggle in this view, "New Neovim per directory": picking a dir starts a new Neovim
    instance there and the app connects to it
<!-- }}} -->


## non-functional remarks

A Note on cloning or imitating Github Desktop, Linear and Meld. The author is grateful to all three for creating those
products and their vision, of how things work, with utmost humility and gratitude. Meld (open source, GPL) is the model for picking either side of a conflict hunk.

## Performance

- a click shows its result in the next frame; the backend answer follows
  - Tasks checkboxes, status and priority: the edit applies in memory, only the edited file is parsed again
  - the reload that our own write sets off is skipped; a reload that started before an edit keeps the edit
  - Changes stage and unstage of whole files: the file moves to the other list at once;
    the status after git answers keeps it there or puts it back, and the error shows
  - hunk staging waits for git: the other hunks' line numbers shift
- an interaction costs what it changes on screen, not what the app holds (2026-11-19)
  - a cursor move (arrows, J/K, a click on a row) moves the highlight: the rows of Add and Ignore,
    Changes and Tasks are built once per change of what they show, not per key
  - a mode switch rebuilds only the mode stack: the mode views stay the same instances until
    their inputs change, so the hidden modes do no work
  - the rail snaps its width; only its labels fade in
  - dragging the edge of the Add and Ignore side pane lays the list and the pane out at the new
    width but rebuilds neither of them
  - hidden modes still lay out on a window resize: a keep-alive stack that skipped them was tried
    on 2026-11-20 and reverted (a hidden mode that changed left dirty semantics and the log filled
    with assertions); do not retry it without a plan for dirty hidden subtrees
  - a window resize over Help freezes the table, scales it uniformly to the new width, and reflows
    150 ms after the last change; descriptions are one line while resizing, and a column never goes
    below 250 px (the right edge clips instead)
  - debug builds show a badge in the middle of the pane being dragged, `width X height` in px
    (orange on deep blue); release builds keep no badge (`lib/ui/resize_badge.dart`)
  - no resizable pane goes below 280 px (Add and Ignore's side pane, Pull request and Changes)
- Settings are read where they are used, not copied at startup: a choice applies at once to the next
  delete, the next wheel notch and the pane, and a restart starts on the saved choices
- UI timing instrumentation, on in debug and profile builds, off in release; `NVIMOS_TIMING=1` / `0` overrides
  - hooked where actions already pass, not in click handlers:
    every backend call (`rpc <module>.<fn>`), the state actions (`tasks.edit`, `changes.stage`, ...)
    with their phases (`/optimistic`, `/paint`, `/git`, `/saved`), and every pointer down to the next frame
  - mode switches: `shell.setMode` (to the new mode on screen) and `shell.railClick` (`/tap`:
    mouse down to the handler, so a gesture that waits shows; `/paint`)
  - `addIgnore.move`: an arrow key to the frame with the new cursor
  - `addIgnore.resizeSide`: a drag step on the side pane's edge to the frame at the new width
  - `help.resize`: a window width change in Help to the frame at the new column layout
  - per action: count, p50, p95, max in ms
  - written to `%APPDATA%/nvimos/ui-timing.json` every minute and on quit: the last 30 sessions and totals

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
