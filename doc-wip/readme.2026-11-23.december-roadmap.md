# December release: a stranger's first fifteen minutes

Work in progress, 2026-11-23. A roadmap for the December release, plus the popularity argument
that shaped it: what the app is defensible for, where the pushback landed, and what is deliberately
parked.

## Where the app is

Thirteen days from the first commit, 259 commits, roughly 25k lines of app Dart and 10k of tests, a
17 MB single-file Windows exe, and a weekly release. The local backend runs git, files, diffs,
staging, commits, the file-first Add/Ignore mode, the Tasks workspace and the Repos crawler without
Neovim. The relay and the editor connection are a bonus for WSL, Docker and SSH, not the spine.

That is the thing worth protecting: **it is a local-first git review app that happens to have a
Neovim door.**

## The one-sentence pitch

The README still says what the app is, not why anyone would use it. The sentence the release should
carry:

> Review any repository, offline, with no account. Branch diffs, hunk staging, commits and the files
> around them in one window, with your editor one key away when you want it.

GitHub integration later is additive. The stance is not anti-forge; it is "the forge being down, or
the internet being gone, does not stop the work." That is a normal engineering requirement, and it
is also the clearest thing to say out loud.

## Popularity: the argument and the pushback

The case that survived:

- **An opinionated workflow is an asset, not a liability.** A coherent set of modes that encodes one
  person's idea of how review should feel is what lazygit, Tig, GitUp and Linear are. The risk was
  never the taste; it was the number of doors at the entrance.
- **The task source is pluggable in location already**, and format-pluggable is planned. Tasks can
  live in a different directory from the project today; external providers (GitHub issues, Linear)
  are a later option, and disabling a mode is one setting.
- **Decoupling Neovim widened the audience.** The default build does not need an editor. That makes
  this a git review app for anyone, with the relay as the remote/WSL/Docker story.
- **Donations, not a product, is a coherent success model.** The bar is a hundred people who love it,
  not a market. That makes "does not break, does not scare people, can be found" the whole game.
- **The 15-minute test is the real product claim.** If a student who has never seen the app can be
  shown the flow in fifteen minutes and feel the same relief, the design has already won.

The pushback that landed, and the corrections:

- "Windows-only" was wrong as a ceiling and only right as current state. Flutter compiles to Linux,
  macOS and Android; this tree has only a `windows/` runner and Windows-shaped seams (`shell32.dll`,
  `attrib`, `cmd /c start`, `explorer.exe`, PowerShell, `%APPDATA%`). It is a port, not a rewrite.
  Android is the exception: local git there needs libgit2 or the remote/relay path, because an app
  cannot exec a `git` binary.
- The "sum of your habits" framing was too harsh. The habits are the asset; the first fifteen minutes
  are the packaging problem. A mode-disable setting plus a guided first run is the fix, not a
  redesign.
- "No forge" was originally read as a gap. It is the differentiator. The gap is only in the sentence
  that sells it.
- The default task format is still OpenSpec/Backlog.md until a provider exists. Fine for the
  prototype; not a December blocker.

## What success means for this release

Four checks, in order of importance:

1. Three people who are not the author complete one flow unaided: open folder, pick two branches,
   read the diff, stage a hunk, commit.
2. One of them can repeat the one-sentence pitch back after using it.
3. A Linux build exists and runs the same local flow; Windows stays the primary build.
4. No data-loss bug in delete, discard, checkout or rebase. The trash default holds.

Popularity experiments are useful but not blocking. They come after the release, and they are
recorded below under "Parked".

## The December roadmap

Four tracks. The order is a proposal, not a promise; the dates are deliberately loose.

### A. The first fifteen minutes (P0, the release's reason to exist)

- A tiny demo repository with a branch that has a reviewable diff, committed in the repo or fetched
  by the app, so the first run has something to show without the user's own work.
- A guided first run: three or four cards over the real UI, in order, ending at a commit. Skippable,
  and never shown twice.
- The mode-disable setting, and a sane default set for a new user: Pull request, Changes, Add and
  Ignore, Repos. Tasks, Settings, Log and Help available but not in the first-run rail.
- A "Start here" page in Help that is the same 15 minutes in text, with the keys.
- The README rewritten around the pitch, plus a 90-second recording of the flow. Record it before
  polishing anything else; the recording exposes what still needs explaining.

### B. Cross-platform proof (P1)

- Add `linux/` and `macos/` runners. Port the seams that already have platform branches: trash,
  hidden-file write, shell launch, editor and terminal detection, prefs paths, the recycle-bin skip.
- CI builds Linux and macOS in addition to Windows. Windows remains the release artifact in December.
- Android is explicitly out: the local backend shells out to git. Note the remote/relay path as the
  future option, and do not promise a date.
- No new Windows-only code in shared paths from here on.

### C. Core review polish (P1)

- One path end to end with no editor: open folder, branches, commit list, file tree, diff, stage and
  unstage hunks, commit, see the new state. Empty states and error recovery included.
- The file browser and preview get the same treatment as the diff: keyboard reachable, no dead ends.
- No new modes in December. The app already has more surface than one release can explain.

### D. Release and donations (P2)

- A version display, a stable download page, and a SHA-256 next to each artifact. Signing is a
  separate decision, not a December dependency.
- A donations link (GitHub Sponsors or Ko-fi) in the README and About, no paid tier, no gating.
- A short "what this is not" note: not a GitHub client, not an IDE, not a task SaaS.

### Rough order

| Week | Focus |
|------|-------|
| 1 | Demo repo, first-run cards, README pitch, the recording |
| 2 | Mode defaults and Help; the core flow end to end without an editor |
| 3 | Linux runner and port; CI build; fix what the port exposes |
| 4 | macOS if Linux was cheap, otherwise polish; download page, checksum, donations; freeze |
| 5 | Buffer. Ship what is solid. Cut, do not slip. |

## Open decisions

- Linux first or macOS first? Linux is the cheaper proof; macOS is the bigger audience for this kind
  of tool.
- Does the demo repo live in the app's repo, or is it generated on first run?
- Guided tour in-app, or the recording first and the tour after the release?
- Which four modes are the default rail for a new user?
- Sponsors or Ko-fi, and does the About page carry it or only the README?

## Parked, on purpose

Not December, and not because they are bad ideas:

- GitHub issues and PRs as a provider; Linear tasks. The external-provider proposal already exists;
  it needs a real user asking for it.
- Android, or any mobile story. Remote-only would be the shape, not local git.
- A richer onboarding than the four cards: sample data, videos per mode, a sandbox repo.
- Adoption experiments: three strangers, one sentence, a post to r/neovim. Useful, and exactly what
  the release should make possible, but the product has to be shippable first.
- Anything that adds a mode, a provider or a platform before the four checks above pass.

## The thing to remember

The app is not a bet on the author's taste being universal. It is a bet that a coherent, fast,
local-first review flow is useful to enough people that a donation link is not embarrassing. The
December release is the first honest test of that, and the fifteen minutes are the test's unit.
