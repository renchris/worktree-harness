# Security Policy

`worktree-harness` is a local developer tool (`git` + `bash`). Its trust model
and the risks it does and does not protect against are documented in
[`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md). In short: **`.harnessrc` is
sourced as bash**, so only run the tool in repositories you trust.

## Supported versions

The latest released tag receives fixes. This is a small, solo-maintained
project — please run the newest version before reporting.

## Reporting a vulnerability

If you find a way to lose data, clobber a branch, push unexpectedly, or
otherwise breach a guarantee in the threat model, please report it privately:

- Use GitHub's **"Report a vulnerability"** (the repo's *Security → Advisories*
  tab), or
- open a minimal issue **without** sensitive details and ask for a private
  channel.

Include `worktree-harness doctor` output and a minimal reproduction. You'll get
an acknowledgement within a few days.
