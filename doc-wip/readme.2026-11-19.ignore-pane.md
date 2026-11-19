# Ignore pane: the match lookup can never match, and how ops differs from Purrage

## The dead match lookup

The pane asks `git check-ignore -v <path>` which rule ignores the row under the cursor. Every row
of the Add and Ignore list is either untracked and not ignored (git status would not list it
otherwise), or tracked. Without `--no-index`, `check-ignore` never reports a tracked file. Neither
app passes it (`lib/local/repo.dart:186` here, the same line in Purrage), so for any row the cursor
can reach the answer is always "no match".

The test `the pane shows the ignore files of the cursor row and moves with the cursor`
(`test/ignore_test.dart`) only sees "Ignored by …" because its fake lookup invents a match.

## The wrong question, not only a dead branch

The cursor can only land on a row the list shows, and the list shows exactly the paths git reports
as changed or untracked. An ignored untracked path is absent, so it cannot be under the cursor. A
tracked path can match a `.gitignore` pattern, but ignore rules do not apply to tracked files, and
without `--no-index` `check-ignore` does not report one. So the pane asks "which rule ignores this
row" about rows that are, by construction, not ignored; the only reachable answer is "not ignored".

That is more than a dead call. It means explaining a row's ignore state is not the pane's job. The
useful job is the ignore surface around the row: the files and rules where a new hide/ignore rule
would go, and where they can be edited. Purrage's rail + lines keeps that job with the match gone.

## What the test actually proves

The test is not evidence the feature works: its `lookup` fake returns a match the real repository
cannot return for a listed row. It does prove rendering, cursor-following and the hover actions,
which are worth keeping. The match assertion is not: a replacement should assert that the rail and
lines follow the row's folder, that a rail pick holds until the folder changes, and that a cursor
move reads no file.

## The Neovim filesystem assumption

The pane and dialog read and write `.gitignore` through `Repo` (`lib/local/repo.dart`), opened on
`session.repo.root` by `AddIgnoreState.ensureRepo()`. That assumes Neovim's filesystem is this
machine's. Neovim may run in a VM or behind SSH, where that root is not a local path.

The ignore operations must move into `RepoBackend`: discover, read, append, replace, create, and
the `.git/info/exclude` target. Both backends implement them: `LocalBackend` delegates to its
`Repo`, `NvimBackend` calls the relay plugin. Paths on the API are repo-relative and the backend
resolves them; no local absolute path crosses it. Open in editor goes through `EditorSession`,
which already takes a repo-relative path and a line.

## Dirname, Flip, and why a line is refused

Dirname only broadens positive rules. Comments and blank lines are not rules; negations are not
moved; a rule with no folder component (`*.log`, `/x.log`, `build/`) has nothing safe to move up;
and a wildcard-only parent (`**/`) is too broad. Each refusal gets its own tooltip.

Flip toggles a leading `!` on a rule line and is disabled on comments and blank lines. Both helpers
are pure and get unit tests for the rule shapes and their variations.

## What goes, what stays

- goes: the match and everything built on it
  - `IgnoreInfo.match` / `isMatch`, `_Verdict` ("No rule ignores it." / "Ignored by …"), the
    highlighted rule, the `checkIgnore` call in `_fromRepo`, the test's "Ignored by" assertion
- stays: the pane as a view of the ignore files that matter for the cursor row (its folder's
  `.gitignore`, the root one, `.git/info/exclude`), with their rules and the hover buttons
  (one folder up, delete); the user keeps hover-only buttons here as an exception, plus a
  right-click menu on the lines
- simpler: the debounce and per-path cache existed for the git call. Without it the content
  depends only on the row's folder: read the ignore files once, again after a refresh or an edit,
  and pick the files for the cursor row's folder synchronously (no timer, spinner or lookup per
  rest)
- same dead branch in the Ignore dialog: its rows come from the same list, so "already ignored by
  … in file:line" and "git already ignores it" never fire (`choice.already`, `alreadyIgnored()`,
  the `checkIgnoreAll` call in `forSelection`)

## ops compared with Purrage's two-pane ignore view

| | Purrage | ops |
|---|---|---|
| Layout | two panes: a rail of every ignore file in the repo, and the selected file's lines | one column: only the files around the cursor row, stacked, each with its rules |
| Which file shows | the file with the match (dead in Purrage too), or the one picked in the rail | fixed by the row's folder; no picking |
| Loading | all files read once (`load()`); `check-ignore` per settled cursor | files read again per path after a 200 ms rest, plus `check-ignore`, cached per path |
| Rule edits | right-click menu: Delete and Dirname; Dirname disabled where there is no folder above (tooltip says why), never makes a wildcard that matches nothing (`**/`), removes the line when the parent rule already exists | hover-only buttons: one folder up and delete; those edge cases untested |
| Files outside the repo | a match in `exclude` or the global file is one line with an Open button | `exclude` listed like the others; the global file not shown |
| Actions | Open in editor, New here (a `.gitignore` in the row's folder) | none |
| Keys | two Tab stops: the rail (`j`/`k` pick a file) and the lines (`j`/`k` scroll); Shift+wheel scrolls the lines | none inside the pane |
| Size | resizable by its left edge, width in prefs, hidden under 900 px window width; a Git lists / Preview switch | fixed 360 px; rules and preview are separate toggles (`p`, `v`) and can be stacked |

The difference is not only layout. In Purrage the match is a shortcut for picking a file in the
rail; the pane still has a reason without it. In Ops the match *is* the pane: no rail, no pick, no
open or create, and the files shown are already chosen by the cursor path. Remove the match and
little is left. That is the case for the proposal's rail + lines, not just a cleanup.

## The CLAUDE.md conflict

CLAUDE.md says the ported Purrage modes carry no hover-only row buttons. Decided: the ignore lines
are an exception (hover buttons stay), and they also get a right-click menu.
