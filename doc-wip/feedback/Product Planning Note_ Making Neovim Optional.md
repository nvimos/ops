# Product Planning Note: Making Neovim Optional

## Source discussion

**User question — 2026-11-12 23:53**

> The connection to nvim, Neovim, is not a hardcore dependency, I don't think. What would I need to do to drop the nvim thing? I guess read the state of the Git repository myself through the Git executable and parse the open spec and backlog files myself, which it already does. What am I getting from the nvim backend that I can't easily re-implement in a standalone mode for this app?

## Assessment

You are probably right: **Neovim does not need to be a hardcore dependency for the core product.** It is currently acting as a convenient local integration layer, not as an irreplaceable source of truth.

The important distinction is:

- **Git state** belongs to the repository and can be read directly with Git.
- **Task state** belongs to Markdown/OpenSpec/Backlog files and can be parsed directly.
- **Editor state** belongs to Neovim and is the part you would lose or need to replace.

## What the Neovim backend currently gives you

### 1. Git operations

The backend currently exposes:

- branches and revisions
- commit history
- diffs
- working-tree status
- staging and unstaging files or hunks
- discarding changes
- checkout
- commits

These can be implemented directly through the Git executable. This is relatively straightforward, although staging individual lines or hunks requires careful patch handling.

You would replace calls such as:

```text
backend.git.status()
backend.git.diff()
backend.git.stageHunk()
backend.git.commit()
```

with a local Git service that invokes commands such as:

```text
git status --porcelain=v2
git diff
git diff --cached
git diff <base>..<head>
git apply --cached
git restore
git commit
```

For performance and correctness, you would probably eventually use Git’s plumbing commands as well as its normal porcelain commands.

### 2. Reading and editing files

The backend provides:

- reading files
- getting current buffer text
- setting selected lines
- creating files
- moving files
- running a CLI
- opening or showing files

Most of this can be replaced with ordinary filesystem access.

The one meaningful difference is that Neovim may contain **unsaved buffer contents** that are not yet present on disk. Your current Tasks implementation deliberately reads through `files.*` so that unsaved Neovim edits appear in the task view.

In standalone mode, you would normally see only saved filesystem state. That is not a serious limitation for a Git/task application, but it is a real behavioral difference.

### 3. Live editor context

The backend also reports:

- current window
- current buffer
- current file
- cursor position
- editor notifications
- buffer changes
- jobs
- Git hints
- window and cursor updates

This is the part that is difficult to reproduce without an editor integration.

The value is not that the app needs Neovim to understand Git. The value is that it can answer:

> “Where is the user currently working, and how can I take them directly there?”

It also allows the app to react immediately when a buffer changes, rather than waiting for the file to be written to disk.

### 4. Opening the exact location

The plan includes behavior such as clicking a diff line and opening that line in Neovim. If the user has unsaved changes, the backend can open a new window instead of disrupting the current buffer.

Without a Neovim connection, you can still:

- open the file with the configured editor
- launch Neovim at a line and column
- open a new terminal or editor process
- use the OS file association

For example:

```bash
nvim +42 path/to/file.ts
```

But you cannot reliably control an already-running editor session unless you use some editor-specific protocol. That is a convenience feature, not a fundamental dependency.

## What you would lose in standalone mode

The main losses would be:

1. **Unsaved-buffer awareness.** The GUI would see files on disk, not unsaved editor contents.

2. **Instant editor synchronization.** The app would need filesystem watchers, periodic refreshes, or explicit refresh operations.

3. **Precise control of an existing editor session.** You could launch an editor, but not necessarily reuse the current Neovim window, tab, or buffer.

4. **Live cursor and buffer context.** The status bar could no longer show where the user currently is in the editor.

5. **Neovim job integration.** Commands currently launched through the backend would instead run as ordinary child processes.

6. **Editor-defined behavior.** Any plugin-specific behavior, such as the tilde checkbox states or custom commands, would need to become part of the standalone app or disappear.

None of those prevents the Pull Request, Changes, Tasks, or Directories modes from working.

## What should replace it

I would split the current backend into independent services rather than replace it with one giant “standalone backend”:

```text
Ops UI
 ├── Repository service
 │    └── Git executable
 ├── Workspace service
 │    └── filesystem + file watchers
 ├── Task service
 │    └── Markdown/OpenSpec/Backlog parsers
 ├── Process service
 │    └── CLI commands and jobs
 └── Editor adapter
      ├── standalone launcher
      └── optional Neovim adapter
```

The key is to make the editor adapter optional:

```text
EditorAdapter
  openFile(path, line, column)
  revealFile(path)
  currentLocation()
  onLocationChanged()
```

Then provide:

```text
StandaloneEditorAdapter
NeovimEditorAdapter
VSCodeEditorAdapter   // possible later
```

In standalone mode, `currentLocation()` can simply return “unknown,” and `openFile()` can launch the configured editor. The rest of the application should not care.

Similarly, define a repository interface:

```text
Repository
  status()
  branches()
  commits()
  diff(base, head)
  stage(...)
  unstage(...)
  discard(...)
  commit(...)
```

Then implement it with a local Git process. Your existing task parser can remain mostly unchanged; it would read from the filesystem rather than `backend.files.*`.

## The harder part is not Git; it is safe process integration

Calling Git is easy for the common path. The challenging details are:

- repository paths containing spaces or unusual characters
- Windows process launching and quoting
- Git worktrees and submodules
- merge conflicts
- renames and deleted files
- binary files
- partially staged files
- line-ending differences
- concurrent changes while an action is being applied
- Git commands that require user input
- authentication and remote operations
- detecting when the repository changes outside the app

You already have an important safety pattern in the task editor: refuse to apply a line edit if the file changed since it was read. The same idea should apply to Git actions. Before staging, discarding, or modifying a task, verify that the expected base state still exists.

## Recommended product direction

I would make standalone mode the **primary architecture** and Neovim an optional enhancement.

That gives you:

- a wider audience
- simpler installation
- fewer connection and version failures
- support for VS Code, Emacs, Zed, or no editor integration
- easier testing
- clearer separation between repository state and editor state

You can preserve the Neovim experience by shipping the adapter later or alongside it. In fact, this makes the Neovim connection more valuable: it becomes a premium integration rather than a requirement.

The minimal standalone version could support:

- local repository selection
- Git branch comparison
- working-tree status
- file and hunk staging
- commits
- Markdown/OpenSpec/Backlog task views
- filesystem watching
- “open in configured editor”

Then the optional Neovim adapter adds:

- unsaved buffer contents
- live cursor and current-file state
- exact window reuse
- buffer-aware task updates
- editor-side commands and notifications

## Short conclusion

**You can remove Neovim without redesigning the product’s core.** You would be replacing the backend’s editor and process integration, not its essential Git or task functionality. The cleanest architecture is to treat Neovim as one optional `EditorAdapter`, while Git, tasks, filesystem state, and application jobs become native services of the desktop app.
