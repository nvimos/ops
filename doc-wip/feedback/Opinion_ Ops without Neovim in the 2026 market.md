# Opinion: Ops without Neovim in the 2026 market

## Source discussion

**User question — 2026-11-13 23:53**

> review plan and the latest git proposal. then do an online search for anything even remotely as good as this for working with git. give me your opinion about this project. am i too positive because it's my own work or is this really a good and super useful product? who would want to use it. imagine it's detached from nvim. like that part can be ripped out and reimplemented as a direct-git-backend without nvim.

Read for this: `PLAN.md`, the OpenSpec change `merge-beside-checkout` (nvimos-meta), the two earlier
notes in this folder, and three web searches. The app was not run.

## Verdict

You are somewhat too positive, but the parts you're proudest of aren't the parts that would make this
a product. Detached from Neovim, it is good and useful to a small, specific group. It isn't broadly
"super useful", and in late 2026 it's no longer a gap nobody has filled.

## What's genuinely strong

- **The merge-beside-checkout proposal is the best thinking in the project.**
  - it merges without a checked-out folder: `merge-tree --write-tree`, `commit-tree`, then
    `update-ref` with the old value as a guard
  - it brings the main checkout forward with `read-tree -m -u`
  - that fixes a real, daily annoyance in agent workflows
  - mainstream GUIs (GitHub Desktop, Fork, Sublime Merge) still check out the branch and refuse when
    the folder has changes; only GitButler thinks in a similar direction
- **It reviews whatever lands on a branch, no matter which agent made it.**
  - the 2026 agent managers (GitHub Copilot app, Conductor, Orca, Claude desktop, Cursor 3, Emdash)
    all review diffs, but only for sessions they launched themselves
  - Ops doesn't care who wrote the branch: Claude Code in a terminal, a cron job, a colleague
  - that's a real position to take
- **Tasks in markdown files next to the git work.**
  - Backlog.md has its own kanban (`backlog browser`), and specdeck is a dashboard for OpenSpec
  - nothing found combines both with branch review and staging in one app
- **Windows and mouse-first.**
  - most agent desktop apps are Mac-first
  - the keyboard-heavy git tools (lazygit, gitui, Magit) live in a terminal

## Where the enthusiasm outruns the product

- **Without Neovim, the Changes and PR modes are commodity, and behind on features.**
  - Fork and Sublime Merge already do staging, hunks, branch compare and commit, plus syntax colours,
    blame, rebase and push
  - the plan lists side-by-side diffs and syntax colours as "later", and there are no remotes at all
  - those modes will be compared with mature apps, not with nothing
- **Many of the most-polished parts only matter to the author.**
  - the D key matched by scan code, middle click arriving as Shift+Insert, the tilde checkbox marks,
    genja-startdirs, the debug bar, the icon history
  - fine for a personal tool, but a big share of PLAN.md is about focus and keys
  - very little covers what a stranger needs: pushing, conflicts, first-run setup
- **The Tasks mode depends on two niche formats.**
  - OpenSpec and Backlog.md are rising with AI coding, but they're early-adopter territory
  - whoever doesn't use either sees an empty mode
- **The earlier "Assessment of the Ops GUI concept" is too generous.**
  - it rated distinctiveness 8/10 before the wave of agent managers went generally available
  - a fair rating now is about 6

## Who would want it

Developers who:

- run several command-line agents (Claude Code, Codex) in worktrees
- plan in OpenSpec or Backlog.md files in the repo
- work on Windows
- want a GUI rather than a TUI, without being tied to one vendor's agent runner

That's thousands of people, not millions, though it's a group that is growing.

One-line pitch: **"the desk where agent work gets reviewed, merged and ticked off, whichever agent made it."**

## If it's cut loose from Neovim

The earlier note "Making Neovim Optional" is right: one service each for Repository, Workspace,
Task and Editor, with Neovim behind an optional `EditorAdapter`.

Picks for the proposal's open questions:

- **One path:** the folder-less merge becomes the only Merge, not a fallback
- **No merge worktree in v1:** a conflict says "this merge has conflicts; do it in a worktree"
- **A file you're editing:** refuse, and name the files that overlap
- **Who runs git:** Ops itself; Neovim only does the unsaved-buffer check and `:checktime`

Then spend the effort on what keeps people in the app:

- syntax-coloured side-by-side diffs
- push and fetch
- linking a task to its branch; that last one is the thing nobody else does

## Sources

The search results came mostly from comparison blogs, so treat the competitors' feature claims as
unchecked.

- [Best Desktop Agent Managers 2026 (runpane)](https://runpane.com/desktop-agent-managers)
- [AI Coding Agent Dashboards 2026 (amux)](https://amux.io/guides/best-ai-coding-agent-dashboards-2026/)
- [GitHub Copilot app GA](https://windowsforum.com/news/github-copilot-desktop-app-ga-2026-turns-ai-coding-into-a-supervised-agent-control-plane.427657/)
- [Review coding agent work (superset)](https://superset.sh/compare/review-coding-agent-work-team)
- [Agentic coding Mac apps compared](https://rywalker.com/research/mac-coding-agent-apps)
- [Backlog.md](https://github.com/MrLesk/Backlog.md)
- [specdeck](https://libraries.io/npm/specdeck)
- [lazygit alternatives](https://alternativeto.net/software/lazygit)
