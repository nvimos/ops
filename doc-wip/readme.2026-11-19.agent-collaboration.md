# Agent collaboration: two subagents on the ignore panes

Work in progress, 2026-11-19. What worked, what did not, and a playbook for the next multi-agent
change.

## The split

One change, two subagents, one shared dirty checkout:

- **Backend agent** — `RepoBackend` ignore API, `LocalBackend`, `NvimBackend`, the new relay
  `nvimos.gitignore` module, backend contract tests and relay Lua tests.
- **UI agent** — Add and Ignore state, the two panes, line cursor, Dirname/Flip/Undo, dialog,
  notices, marker, responsive side area, pure helpers, Ops widget/state tests and PLAN/Help.

The proposal and tasks were committed in `nvimos-meta` first (`28c8e3f`), then both prompts pointed
at the same files and a fixed API contract.

## What worked

- **Design first, code second.** The proposal was already settled before spawning, so the agents
  were implementing a decision, not arguing about one. The commit also gave both a stable document
  to cite.
- **A fixed API contract in both prompts.** The exact model names, method names and semantics of
  `IgnoreFileRef`, `IgnoreSnapshot`, `loadIgnorePanes`, `untrackedIgnoreFiles`, `readIgnoreFile`,
  `appendIgnoreLines`, `replaceIgnoreLine`, `insertIgnoreLine` and `createIgnoreFile` were written
  out before either agent started. The UI agent could code against the contract while the backend
  agent built it.
- **Disjoint ownership, tests included.** The split was not just “backend vs UI”: each prompt named
  the exact files it owned, including tests, Help and PLAN. That kept both agents out of the same
  files.
- **Backend-first ordering happened naturally.** The backend agent finished first; its contract
  details (`text` is null only when there are no files, untracked returns nested files only, insert
  validates 1..lineCount+1) were passed to the running UI agent as a follow-up. That small relay
  closed the gap without stopping either agent.
- **Both agents reported their tests**, not just “done”: relay `13/13`, backend contract `2/2`,
  local repo/parity `34/34`, UI/pane `48/48`, then the lead ran the integrated set again.
- **Agents did not commit.** The lead kept commit authority and could review before anything entered
  history.

## What was awkward

- **One dirty checkout, many unrelated changes.** The Ops working tree already had dozens of
  modified and untracked files. Agents were told not to revert or reformat unrelated files, but
  attribution is still hard: `git diff` is large and mixed, and a mistake in an unowned file is easy
  to miss. A worktree per agent would make this cleaner when the change is large or the tree is
  dirty.
- **Agents cannot talk to each other.** The lead is the message bus. The backend contract landed
  while the UI agent was still working; the lead had to notice and forward the details. That worked,
  but it is a manual step that should be planned for.
- **The contract can drift in small ways.** The backend agent added useful semantics (a selected file
  not yet discovered is included; `text` is null only with no files) that were not in the prompt.
  The UI agent was told after the fact. Put “report every deviation from the contract” in the prompt,
  or make the backend agent write the interface stub first and pause before implementing.
- **Flutter commands contend on the startup lock.** Parallel analyze/test runs wait on the same
  Flutter lock. Agents can still work in parallel, but the final analyze/test sweep should be
  sequenced by the lead.
- **“Done” has layers.** The UI agent left two manual checks open and noted one edge case about the
  dialog’s untracked nested `.gitignore` target list. The lead fixed the edge case and ran the
  integrated tests. An agent’s completion is not the change’s completion.
- **Scope words need examples.** “Backend” and “UI” are not file boundaries. The useful split was
  layer plus exact file list plus exact API. Without that, both agents would have touched
  `ignore_choice.dart` or the backend models.

## Playbook for next time

1. **Commit the decision before spawning.** Proposal, tasks and the API contract are the shared
   source of truth.
2. **Write the contract as code-shaped text.** Signatures, types, null/empty semantics, path rules
   and error behaviour. “One load then untracked” is not a contract until it is method names and
   return shapes.
3. **Publish an ownership table.** Include source, tests, docs and generated files. Name the files
   each agent must not edit.
4. **Split by layer or repository, not by “frontend/backend” intuition.** The relay and the local
   backend belong together; the pane state and its widgets belong together; the pure line logic can
   go with either, so assign it explicitly.
5. **Let the backend define the interface first when possible.** If a stub can land quickly, the UI
   agent can compile against it instead of a prompt.
6. **Use a worktree per agent when the tree is dirty or the change is large.** Disjoint files are
   enough for a small change; they are not a substitute for isolation.
7. **Keep the lead as integrator.** The lead relays contract changes, fixes small integration gaps,
   runs the final analyze/test set, and commits.
8. **Have agents report deviations, not just summaries.** “What I changed from the contract” is more
   useful than a file list.
9. **Separate code-complete from actually verified.** Manual walkthroughs and remote checks stay
   with the lead unless an agent can really run them.

## Idea: a local test broker

Discussed after the change: should another agent own a test queue, so builders submit test files
and wait for a result instead of each running Flutter?

It makes sense as a concept — a local build/test broker — but not as another agent. Queueing,
deduplicating and running tests is deterministic and does not need judgement. An agent would add
latency, tokens, another context that can be wrong and another process that can hang. A small CLI
or daemon is the right shape.

The useful feature is **in-flight deduplication**, not a five-second batch window:

- if the same test command is already queued or running, join it and share the result;
- otherwise run it under one global lock;
- do not cache across code changes.

A batch window adds five seconds to every request and makes per-file results harder to read. A
matching in-flight run does not.

What to do first, in order:

1. builders run only their targeted tests, never the full suite;
2. the lead runs the final integrated set;
3. one global Flutter lock serializes `flutter analyze` / `flutter test`;
4. optional: join an identical in-flight command and return the same log and exit code;
5. only with three or more regular builders, consider a real queue daemon with timeouts, stale
   leases and per-request result files.

A test queue does not fix the bigger shared-tree risk: a test can run while another agent is
halfway through an edit. Worktrees per agent fix that; the queue only serializes execution.

Verdict: worth a small lock/dedupe tool if multi-agent work becomes normal; not worth a separate
agent, and probably not a full service for two builders on a 2–3 minute suite.

### More thoughts on the test broker (second session)

- **Join only a run that started after your last edit.** In one shared checkout, a run that started
  before my edit tests the old code. The rule is simple: join an identical command only if it
  started after the joiner's last file write. Otherwise queue a new run.
- **Most of the saving comes from running the right files, not from the queue.** Dedupe helps only
  when two builders ask for the same file. Usually they ask for different files, and then the queue
  saves CPU contention but not test time. "Fewer tests in the end" comes from targeted runs plus
  one integrated run by the lead.
- **The CPU problem is concurrency times concurrency.** Two agents each running `flutter test` with
  4 files at a time means 8 test isolates plus two compilers. A global lock caps this at 4, which
  is the actual goal. In this session the Neovim tests flaked at concurrency 4 and passed at 1; two
  agents' runs on top of each other make that worse, and the flake looks like a regression.
- **The broker should own cleanup and timeouts.** It already holds the process, so it can apply the
  per-command timeout, kill leftover headless `nvim` processes and count `%TEMP%\nvimos_*` before and
  after. Today each agent does that check itself, and with two agents the count is wrong: another
  agent's run adds and removes folders in the middle of mine.
- **Waiting is already free for an agent.** A test run in the background notifies the agent when
  it ends, so a builder can queue and keep editing. That's an argument for a plain lock wrapper
  (`make test` taking a named mutex) rather than a service with its own wait protocol.
- **Smallest useful version:** `make test` takes a machine-wide named mutex around `flutter test`,
  and prints "waiting for the test lock (held by <pid>, <files>)" so the wait is visible. Add dedupe
  only if logs show identical commands overlapping.

## Seen from an agent working beside others (second session)

This session was not the lead of the two-agent split. It worked in the same checkout while the
user and other agents edited files. What showed up from that side:

- **Files change under you.** `add_ignore_view.dart`, `help_view.dart` and the `ops-ignore-pane`
  proposal were edited by someone else between my reads. The Edit tool refuses a stale file, which
  is the real safety net. Keep each edit small and re-read only the part you change; never write a
  whole file from an old read.
- **A test failure can be someone else's half-done edit.** Before calling a failure a regression,
  check `git diff` for the file the trace names, and whether this session touched it. The known
  flakes (concurrency 4, `archive merges deltas`) are listed in CLAUDE.md for the same reason.
- **Rules written mid-session don't reach running agents.** I added the proportional-work rule to
  CLAUDE.md, and a little later the side pane's drag edge turned out to be the same kind of bug,
  in code written before the rule existed or by an agent that never saw it. A new rule should be sent to the running
  agents by the lead, and a review pass should check new code against it ("does a drag, key or
  cursor move rebuild more than it changes?").
- **Builders forget the bookkeeping.** The proposal rescan found the merge conflict view and merge
  beside checkout built, while their status lines and backlog tasks (TASK-143 to 153) still said To
  Do. Code got done, the status did not. Either each builder moves its task status in the same
  change, or the lead does it at integration, but the prompt has to say which.
- **Machine-read conventions belong in the prompt.** The proposal parser takes the first `TASK-<n>`
  on the `Status:` line as the change's task. A free-text status note that mentions another task
  silently relinks the change. A builder editing status lines needs that rule spelled out.
- **One SDK, one lock.** A second Flutter SDK (`H:/flutter`) rewrote `package_config.json` and
  broke the live app's hot reload. With several agents, any one of them picking the wrong SDK
  breaks all of them, so the SDK path goes into every builder's prompt, not just CLAUDE.md.
- **Same-tree agents can't share a cleanup check.** "The count of `nvimos_*` folders is the same
  before and after" only works with one test run at a time. With several, each agent should check
  that its own folders are gone, or the broker does it.

### Additions to the playbook

10. Name the bookkeeping owner: who moves task statuses and proposal status lines.
11. Send rules added during the run to the running agents; review new code against them.
12. Put machine-read conventions (status-line task ids, ordinals, SDK path) into the prompt.
13. Before treating a failure as a regression, check whether the file is someone else's work in
    progress.

## Three stacks in worktrees (Purrage, 2026-11-17/18)

A bigger run, done the other way: not two agents in one checkout, but three long-lived agents
(stacks A, B, C), each in its own worktree under `.claude/worktrees/stack-*`, each building a chain
of six or seven task branches (`PR-<slug>`, one commit per task, `Stacked-On:` trailer, merge
position in the task file). 19 tasks in all; a fourth stack (tests) waits for the end. The lead
planned, relayed, answered the user, and joined the stacks afterwards.

### What worked

- **Worktrees removed the attribution problem.** Every diff in a worktree was that agent's. No
  "don't touch unrelated files" clause was needed, and nobody's half-done edit broke another's
  test. This is the fix for most of "What was awkward" above.
- **Stack by dependency, not by layer.** Tasks were put into stacks by which task needs which
  (foundation seams → workspace → actions; performance; small UI fixes). Inside a stack each branch
  builds on the one before it, so a later task can use an earlier one's code without waiting for a
  merge. Between stacks there were no dependencies, only overlapping files.
- **A merge order written down before the work.** Every task file opened with `Merge N of 21`, the
  commits carried `Stacked-On:`, and the lead kept an ASCII tree of branch → task → commit →
  status. The user asked for that tree several times while the agents worked; it was the one view
  of the whole run. (It became a proposal: a Stack view in Ops' History mode.)
- **Joining by rebase, done by the agent that owns the code being moved.** The lead created
  `develop`, tagged every stack tip (`pre-join-a/b/c`) so nothing could be lost, started
  `git rebase --update-refs --onto <previous stack tip> main <stack tip>` and handed the stopped
  rebase to that stack's own agent with a summary of what had changed underneath. The agents
  resolved each commit into the new structure (B's work into A's `Workspace`, A's process seam,
  A's widget atoms) instead of keeping their own copies, kept every commit analyze-clean on its
  own, ran the full suite at the tip, and reported the new hashes. `--update-refs` moved all the
  intermediate branches in one go. 13 + 12 commits rebased, 286/286 tests at the end.
- **Resuming an agent keeps its context.** When the disk filled up mid-run, the agents stopped;
  after the user freed space, a `SendMessage` to each one continued exactly where it was, with
  new rules attached. Re-spawning would have cost the whole context again.
- **The lead used the waiting time.** While two stacks ran, the user and the lead designed the
  Stack view (questions read aloud, one at a time) and wrote it up. Agents in the background make
  the lead's own time free, not idle.
- **Reports had a fixed shape**: branch → hash → ACs met → tests, then behaviour changes, then
  "decisions for the user". The last part is what the lead passed on; the rest was checked
  against `git log` before telling the user.

### What went wrong

- **One agent killed everyone's tests.** CLAUDE.md said "if a test hangs, kill it:
  `Get-Process flutter_tester,dart | Stop-Process`". Written for one developer, it is a broadcast
  kill with three agents. Two agents ran it (one while the disk was full), and other stacks' runs
  died and looked like failures. The rule became: stop only the process you started (note its
  PID), and rerun once before treating a killed run or a locked file as real. **Every "kill",
  "clean" or "reset" instruction in a project file has to be re-read as if ten agents ran it at
  once.**
- **A shared machine resource ran out.** Three Flutter builds plus test temp folders filled C:.
  The symptom was an interrupted test run and a failed edit, not "disk full". Check free space
  before fanning out, and give each agent a rule for it (stop and report, don't clean up others').
- **Global counters don't work with parallel agents.** "The count of `purrage_*` temp folders is
  the same before and after" was checked by every agent and was wrong for all of them while the
  others ran. The fix that worked: each test file fails if *it* leaves a folder behind
  (`flutter_test_config.dart`), so the check is per run, not per machine.
- **"Don't edit CLAUDE.md, I'll do it at the join" was broken anyway.** The agent that did it had a
  good reason (its rebase made two lines false). The rule should have said what to do instead:
  "write the CLAUDE.md change into your report", so the lead applies it once.
- **Decisions surface late and twice.** Stack B kept a "stop tracking" option that the user had
  removed in stack C's task. Neither agent knew the other's decision; the lead caught it at the
  join and told C's agent to remove it everywhere. User decisions that cut across stacks have to
  go to every running agent when they are made, not at integration.
- **Agents built things the next stack replaced.** Stack C hand-wrote a help table and a key list;
  stack A (underneath) generated the same table from key bindings. At the join C's version was
  dropped. Overlap between stacks was known in the plan; a line per overlap in each prompt ("A will
  generate the help table; don't build your own, leave a TODO") would have saved the work.

### What the lead does in a run like this

1. Plan the stacks from the task dependencies, write the merge order into every task file.
2. One worktree per stack, from the local base branch; the prompt names the branch chain, the
   tests to run per task, and the machine rules (no broad kills, the SDK, disk).
3. Relay: user answers to the agent that asked; cross-stack decisions to all of them.
4. Keep the tree of branches and states current; it is what the user asks for.
5. Verify reports against git before passing them on.
6. Join: tag the tips, rebase stack by stack with `--update-refs`, hand each stopped rebase to
   the agent that owns the moved code, full suite at the end, then update the project's
   instructions once, from what the agents reported.
7. Land on an integration branch (`develop`), not `main`; the user merges.

### Additions to the playbook

14. Prefer a worktree per agent; a shared checkout only for a small change with disjoint files.
15. Read every destructive or machine-wide command in the project's instructions as if all agents
    ran it at once; scope it to "what you started".
16. Check shared resources (disk, SDK, locks) before fanning out, and say what to do when they run
    out.
17. Make cleanup and leak checks per run, not per machine.
18. Tag before any history rewrite; join on an integration branch.
19. Rebase conflicts go to the agent that wrote the commit being moved, with a summary of what
    changed underneath it.
20. Resume a stopped agent with a message; don't re-spawn it.
21. Agents report instruction-file changes instead of making them; the lead applies them once.

## Result

The split produced the backend and frontend in one pass with no file collisions. The integrated
checks passed: `flutter analyze lib`, 50 pane/state/helper tests, 34 local repo/parity tests and 13
relay tests. The remaining work is the interactive in-app walkthrough and the remote-Neovim check.

The main lesson: two agents are useful when the boundary is a real interface with a written
contract. They are risky when the boundary is only a word like “backend”.

## Two peers with a coordination file (Purrage integration, 2026-11-19)

This was the other shape: two agents (DeepSeek and Claude) working as peers, not a lead with
subagents. Each had its own task list and its own worktrees, and the shared board was
`backlog/docs/doc-76 - purrage integration coordination.md`: proposals with an `integrate-purrage`
tag, 36 backlog tasks, stage order, dependencies, claim log, interface-change log and handoff notes.
Ops was the product; Purrage became its Add and Ignore mode.

### What worked

- **The board, not the prompt, was the source of truth.** A task had an id, an owner, a stage, and
  dependencies. Either agent could see what was open and what was next without asking the other.
- **Worktree per task, branch per task.** `task-<n>-<slug>` from local `main` kept every diff
  attributable and every test isolated. It also made a failed experiment cheap to throw away.
- **Stage gates and dependency order.** Seam → local read-only → actions → discovery → UI. A later
  stage could be built in parallel only where its dependencies allowed, and merges waited for the
  earlier stage.
- **Task files as contracts.** Each task named its files, acceptance criteria and verify steps. That
  was enough for two different agents to implement the same interface without sharing a conversation.
- **Interface-change log.** `RepoBackend`, `EditorSession`, `StatusStore`, `ActionQueue`, the local
  file model: the moment one agent changed a shared shape, the change went into the log before the
  other agent coded against it.
- **Explicit reassignment.** TASK-178 and TASK-180 were pure UI and depended on views another agent
  owned, so they moved to Claude. The move touched the task files, deps, the board table, the counts
  and a handoff entry together. Reassignment is a real change, not a one-line edit.
- **Verified-by in the claim log.** `Needs Test` had a named person instead of an assumption.
- **The user stepped in on process, not code.** “Don’t run the tests several times per task; run them
  at handoffs and integrations” was the right correction. Tests per edit felt thorough and were
  mostly wasted time.

### What was awkward

- **Task numbers are not merge order.** TASK-184/185/186/188 were created after 183 but belonged to
  earlier stages. The board needed an explicit note; otherwise “lowest number next” silently merges
  a later stage first.
- **Parallel merges into the same main ref fail.** Two `git merge` commands started at once produced
  a ref-lock failure and a staged tree that looked like the previous merge had deleted its files.
  Recovery was `git reset` plus a stash of the leftover worktree, then merging again. With
  worktrees, the integrator still has to merge one branch at a time.
- **Two agents can edit one file even in different tasks.** `LocalBackend` was touched by the
  read-only backend, the actions, the task-edit and the file/trash tasks. The dependency chain kept
  them mostly sequential, but a follow-up fix landed on an older branch and had to be merged twice.
  Same-file work belongs on one branch chain, or gets a short “do not touch this file” note.
- **“Done” has layers.** The task board ended with every task at `Needs Test`, none at `Done`;
  implementation was complete, verification was not. A final integration task (TASK-183) is the only
  place that can declare the programme done, and it stayed open for manual walks.
- **Missing backend surface was discovered mid-run.** Local tasks mode needed `setLines`, `create`,
  `move`, `startJob`, `cancelJob` and `cli`; none had a task. They became TASK-184/185 after the
  gap was found. That is acceptable if the task is written before the work, not after.
- **The first board had a mapping error.** TASK-155 was listed under the backend-seam proposal but
  implemented the local git foundations. Proposal task lists, task descriptions and dependencies
  are three places that must agree; a review pass found it.
- **Subagent “done” reports are optimistic.** One said `lib/local/browser.dart` was written while
  the test thread could not see it yet; another wrote tests before the code landed. The lead has to
  check the files and run the boundary test, not trust the summary.
- **The meta repo is a test input.** `tasks_meta_test` reads every OpenSpec proposal. Untracked
  proposals without a `TASK-` id, and binary audio files in a proposal folder, make the suite fail
  for reasons unrelated to the code. Test the product, but know when the planning repo is the
  failing input.
- **The full suite is a resource, not a reflex.** Two agents each running `flutter test` contend on
  the Flutter lock; a full run took ~9 minutes here, and the known `archive merges deltas` flake
  reappeared under load. Targeted tests while coding, one integrated run at the handoff, is the
  useful rhythm.
- **The two agents still cannot talk.** Handoff entries in the doc are asynchronous notes, not a
  conversation. A direct question waits until the other agent reads the file. Keep decisions that
  affect both in the doc, and keep them short enough to be read in one pass.
- **The product and the source repo can move at different speeds.** Purrage was frozen after the
  hand-off was removed; Ops kept changing. “Integrated” meant one app and one mode, not one
  repository.

### Additions to the playbook

22. Make the board the contract: task id, owner, stage, dependencies, claim and handoff entries.
    Prompts and chats are transient; the board survives both agents.
23. Use task numbers as identifiers only; write the merge order separately and update it when a new
    task lands in an earlier stage.
24. One integrator merges into `main` at a time. Worktrees remove edit collisions, not ref collisions.
25. Put same-file work on one branch chain; a dependency edge is not a file lock.
26. Run targeted tests while coding and one integrated set at a handoff. Do not turn testing into the
    main activity of a task.
27. Treat “code complete”, “merged”, “verified” and “programme done” as four different states.
28. When a task is missing, add it before the work and say so in the handoff; do not grow the current
    task silently.
29. Reassigning a task is a board-wide edit: files, deps, table, counts and a handoff line.
30. Check the other agent’s file state before believing a completion message; test the boundary
    yourself.
31. Know which repository is the product and which is the source. Freeze the source when its code has
    moved, and commit the hand-off removal separately.

