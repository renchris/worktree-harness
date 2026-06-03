<!-- Thanks for contributing! Keep changes focused and dependency-free. -->

**What & why**
Briefly: what this changes and the problem it solves.

**Checklist**
- [ ] `shellcheck bin/worktree-harness lib/*.sh share/shell/bash.sh` is clean
- [ ] `bats test/` passes (added/updated a test for the change)
- [ ] No new runtime dependency (git + bash only)
- [ ] bash 3.2-safe (no `declare -A`, `mapfile`/`readarray`, `[[ -v ]]`, `${var^^}`)
- [ ] Docs updated if behavior or config changed (README / docs / `init` template)
