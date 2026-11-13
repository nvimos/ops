# What is a worktree

A git worktree is a second working folder of the same repository, checked out on its own branch.
- one repo, one history, one `.git`: commits made in any worktree are visible from all of them
- each worktree has its own files on disk and its own branch; a branch can be checked out in only one worktree at a time
- edits in one worktree don't show in the others until they are committed and merged

## Why the background sessions use them

Several Claude sessions can work on this repo at once, next to your own uncommitted edits.
- each session gets its own folder under `.claude/worktrees/<name>`, on a branch `worktree-<name>`
- nothing a session writes touches your checkout (`~/es/nvimos-poc-frontend`, on `main`) until you merge it
- `/prish` finishes one: commits, rebases, renames the branch to `PR-<name>`
- `/prish-merge` merges every `PR-*` branch into your checkout and removes the worktrees

## What it does not isolate

Only this repo.
- edits to `~/es/nvimos-meta` (OpenSpec changes, backlog tasks) or `../nvimos-poc-backend` go straight into those checkouts
- they show at once in your terminals and in Ops' Tasks mode, while the code sits in the worktree
- so a session should say, per repo, where its work landed

## Seeing them

- `git worktree list`: every worktree, its commit and branch
- `git log --oneline main..PR-<name>`: what a finished worktree adds
- the folder itself: open `.claude/worktrees/<name>` to read its files before merging

## Example

This file was written in the worktree `what-is-a-worktree`, on branch `worktree-what-is-a-worktree`.
It is not in your checkout until that branch is merged.
