# How do other people work with coding agents: review, commits, merging?

The question: planning commits, reviewing and merging by hand, and building a review app (Ops) around it.
Is that how others do it, or do they let the agent do more on its own?

The sources are mostly blogs and vendor material, not a poll. This is the shape of the conversation,
not a consensus.

## What people seem to do

- Many give each agent its own worktree and branch, then review each branch's diff and run its tests
  before merging. Some keep a separate review worktree, so one branch can be read while another agent
  keeps working.
- Agents produce code faster than people can review it, so review is described as the bottleneck.
  Most sources land on a hybrid: automated checks first, a human on the risky parts. One June 2026
  preprint argues human review is no longer necessary; the other sources push back on that.
- A study of about 25,000 agent-made pull requests found that in about 79% of them the same person
  both reviewed and modified the agent's work. Oversight sits with one person.

## Where this setup differs

- It is on the hands-on end: commits are planned before they happen, review is hunk by hunk, and
  merging is local with no GitHub in the loop. Many people let the agent commit, push and open the
  pull request, then review afterwards. A difference of degree, not a different practice.
- Ops goes after the bottleneck people complain about: a fast review tool is the part the write-ups
  say is missing.
- The undo-discard proposal (`nvimos-meta/openspec/changes/ops-undo-discard`) fits common interface
  advice: make an action easy to take back instead of asking before it.

Nothing in the setup looks out of step with what people are doing now, and the sources disagree on
how much review to keep.

## Sources

- [AI pair programming in the agentic SDLC: When review becomes the bottleneck](https://www.coderabbit.ai/guides/ai-pair-programming)
- [3100 Opinions on Code Review in an AI World](https://www.alphaxiv.org/abs/2607.07980.md)
- [Code Review in the Age of AI](https://addyo.substack.com/p/code-review-in-the-age-of-ai)
- [As AI helps us write more code, who's catching the bugs](https://leaddev.com/ai/as-ai-helps-us-write-more-code-whos-catching-the-bugs)
- [AI coding agents reduce human code review](https://letsdatascience.com/news/ai-coding-agents-reduce-human-code-review-51ea63b5)
- [The Human Review Bottleneck: Practical Code Review Strategies for Agent Output](https://codex.danielvaughan.com/2026/05/24/human-review-bottleneck-code-review-strategies-agent-output/)
- [Git Worktrees Are the Future (Parallel Agents)](https://codingwithroby.substack.com/p/git-worktrees-are-the-future-parallel)
- [Claude Code worktree workflow](https://www.promptlayer.com/glossary/claude-code-worktree-workflow)
- [Git Worktrees with Claude Code (Better Stack)](https://betterstack.com/community/guides/ai/git-worktrees-claude/)
- [Parallel worktrees (Mintlify, pro-workflow)](https://www.mintlify.com/rohitg00/pro-workflow/concepts/parallel-worktrees)
- [Claude Code worktrees (StackNotice)](https://stacknotice.com/blog/claude-code-worktrees-2026)
- [Run three AI coding tasks in parallel, then review each change](https://superset.sh/blog/parallel-coding-agents-guide)
