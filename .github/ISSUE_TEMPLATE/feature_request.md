---
name: Feature request
about: Suggest an improvement
labels: enhancement
---

**The problem**
What workflow is awkward or impossible today?

**Proposed solution**
What you'd like `worktree-harness` to do. If it touches config, sketch the
`.harnessrc` key(s).

**Scope check**
worktree-harness is deliberately small: isolate worktrees, provision them, and
fast-forward them back safely — zero runtime dependencies beyond git + bash.
Does the request fit that scope, or is it better as a `HARNESS_SETUP` hook in
your own project?

**Alternatives considered**
