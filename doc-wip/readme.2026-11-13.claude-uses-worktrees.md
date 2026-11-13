# Claude uses worktrees

A git worktree is a second working folder of the same repository, checked out on its own branch.
- one repo, one history, one `.git`: commits made in any worktree are visible from all of them
- each worktree has its own files on disk and its own branch; a branch can be checked out in only one worktree at a time
- edits in one worktree don't show in the others until they are committed and merged

## When Claude makes one on its own

Claude Code puts its worktrees in `.claude/worktrees/<name>`, on a branch `worktree-<name>`.
- a background session (a job, like this one) must enter one before its first edit
  - the harness rejects file edits in the shared checkout until it does
  - reading, searching and answering need none: such a session works in place
- a subagent started with `isolation: "worktree"` gets its own, removed again if it changed nothing
- an ordinary chat session makes one only when asked
  - you say "worktree", or `CLAUDE.md` / memory says to use one
  - or you start it with `claude -w [name]` (`--worktree`), which puts the whole session in one
- where it branches from: the setting `worktree.baseRef`
  - `fresh` (the default): from `origin/<default branch>`, so local commits on `main` that are not pushed are not in it
  - `head`: from your current local HEAD
  - example: this worktree started at `origin/main` (675d176), without the unpushed `main` commit d127e80

## What the session does with it

The rules a background session gets:
- commit its work in the worktree before it finishes, without asking
- push the branch if the repo has a remote (`origin` here is `nvimos/ops` on GitHub)
- never push to `main`, never force-push, never merge
- open a draft pull request when the task calls for one
- end with a report: what it did, the branch, the PR if any, the next command

An interactive session leaving its worktree asks you: keep it (folder and branch stay) or remove it.

## The intended workflow for people

Claude Code's design is the ordinary branch-and-review flow; Claude does not merge back on its own.

### My stance: local first, no corporate forge

I'm a free software person; my local work should not have to go through a corporate service like GitHub.
- the local flow below (`/prish`, `/prish-merge`, plain `git merge`) is the one I use; it needs no network
- the session rule "push the branch if the repo has a remote" is what pulls GitHub in; my own instructions
  override it, so a line in `~/.claude/CLAUDE.md` turns it off:
  `Git stays local: never push, never open pull requests.`
- if I want review or sharing later, free software ways:
  - `git format-patch` / `git am`, patches by mail (the kernel and sourcehut way)
  - a self-hosted Forgejo for pull requests on my own box
  - a bare repo (`git init --bare`) on a disk or an SSH host as the remote
- `/code-review` is built into Claude Code (not one of my skills, not a plugin); with no argument it reviews
  the local diff, no GitHub needed; `/code-review ultra` runs in Anthropic's cloud, and `--comment` posts to a
  GitHub PR, so leave those out for local-only work
  - the separate `code-review` plugin in the official catalog (not installed) works only on GitHub PRs

### With GitHub pull requests (the default design, not mine)

1. the session commits on `worktree-<name>` and pushes the branch
2. it opens a draft PR, or you open one from the pushed branch (`gh pr create --draft`)
3. you review the diff on GitHub (or with `/code-review <PR#>`), ask for changes in the session or in PR comments
4. you mark it ready and merge it on GitHub
5. `git pull` in your checkout; delete the worktree (`git worktree remove .claude/worktrees/<name>`) or let the session's exit prompt do it

Fits a team, CI, or work you want to read as a diff before it lands.

### Locally, without GitHub (what I use)

Your skills `/prish` and `/prish-merge` do the merge on your machine:
1. in the worktree session, `/prish`: commits leftovers, rebases onto your local branch if it moved, renames the branch to `PR-<name>`, leaves and unlocks the worktree; no push, no merge
2. in your main checkout, `/prish-merge`: merges every `PR-*` branch into the current branch, then removes those worktrees and branches

Fits a solo repo with several sessions at once. Telling Claude "merge it back" in a session also works, but
the session rules forbid merging unasked, so you have to say it plainly.

### Checking before you merge

- `git worktree list`: every worktree, its commit and branch (`[PR-...]` ones are waiting for `/prish-merge`)
- `git log --oneline main..<branch>`: what a branch adds
- `git diff main...<branch>`: the change itself
- open `.claude/worktrees/<name>` in the editor, or run the app from there, to try it before merging

## What it does not isolate

Only this repo.
- edits to `~/es/nvimos-meta` (OpenSpec changes, backlog tasks) or `../nvimos-poc-backend` go straight into those checkouts
- they show at once in your terminals and in Ops' Tasks mode, while the code sits in the worktree
- so a session should say, per repo, where its work landed

## Example

This file was written in the worktree `what-is-a-worktree`, on branch `worktree-what-is-a-worktree`.
It is not in your checkout until that branch is merged (`/prish`, then `/prish-merge`).
