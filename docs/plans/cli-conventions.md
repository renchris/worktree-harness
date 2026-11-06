# Remediation plan: worktree-harness (CLI design guidelines)

## Phase 0: Agent Team Orchestration

**Execution locus per wave.** Every wave is **S**: a dispatched handoff session per unit, using `handoff-fire.sh --prompt-file <unit brief = this plan's unit row + its section> --worktree <branch> --notify-back <lead-uuid> --goal '<end state> — proven by <command>; do not <constraint>'`. No wave runs as T (teammates) or L (lead-inline). The work is code changes across 11 files plus tests, and it should not land in the lead's window.

| Wave | Locus | Sessions | `--goal` (one end state per fire) |
|---|---|---|---|
| A | S | U-A | "lib/common.sh provides the A.1 API and test/common.bats is green — proven by the session running `bats test/ && shellcheck bin/worktree-harness lib/*.sh share/shell/bash.sh` and printing bats' final `N tests, 0 failures` line; do not change any exit code or any stdout output" |
| B | S | U-B1..U-B6 in parallel, then U-B7 | per unit: "<unit's items> implemented with the listed bats tests green — proven by printing `bats test/` summary plus `git diff --stat main` limited to the unit's owned files; do not edit files outside the unit's ownership row, do not change exit codes on non-zero paths or the `new`/`--porcelain` stdout bytes" |
| C | S | U-C1, then U-C2 (serial) | per commit: "<C-item> landed with its callers updated in the same commit — proven by printing `bats test/` summary and `git show --stat HEAD`; do not start an item marked DECISION until the operator's choice is written into the brief" |
| A (R2) | S | U-A2, after U-A1 (the round-1 U-A, renamed) | "lib/common.sh provides the A.3 API (`--cwd`, `--version` at any depth, `wh_deprecated`, parse-only hook, JSON error writer, guidance helpers) and test/common.bats is green — proven by `bats test/ && shellcheck bin/worktree-harness lib/*.sh share/shell/bash.sh` final lines; do not change any exit code or any stdout output" |
| B (R2) | S | U-B8 in parallel with U-B1..U-B6; U-B9 after U-B7 | U-B8: "install.sh parses argv, never installs from a guessed source, refuses src==dest, swaps atomically, and reports clone failures — proven by printing the `bats test/install.bats` summary, a clean `shellcheck -s sh install.sh`, and the ci.yml:60-61 smoke; do not change install.sh's zero-argument exit 0 or which stream any existing line uses". U-B9: "`help --all --json`, `help search` and `<cmd> --help --json` work from lib/help_meta.sh and the drift and presentation tests are green — proven by the `bats test/` summary; do not change any command's behaviour" |
| C (R2) | S | U-C3, after U-C1 and before U-C2's release commit | per commit (C6, then C7): same goal shape as row C |
| B (R2b) | S | U-B8 (goal replaced), then U-B10, then U-B11. Serial, because all three edit `install.sh`, which `curl \| sh` needs as one file | U-B8: "install.sh is wrapped in `main()`, parses argv with help first, never installs from a guessed source, validates its source before any write, refuses src==dest, swaps by rename, and cleans up on every exit and signal — proven by printing the `bats test/install.bats` summary, a clean `shellcheck -s sh install.sh`, and the ci.yml:60-61 smoke; do not change install.sh's zero-argument exit 0, any non-zero exit code, or which stream any existing line uses". U-B10: "install.sh failures, next steps and receipts follow B8 rows 6, 8-12 and Section B10 — proven by printing the `bats test/install_output.bats` summary and the ci.yml:60-61 smoke; do not change any exit code or which stream any existing line uses". U-B11: "`sh install.sh --json` prints one document, or one error line on stderr, per Section B11 (or the R422 exception if D-R2-15 says so) — proven by the `bats test/install_json.bats` summary; do not change any non-JSON output" |
| C (R2b) | S | U-C3 gains C8 | per commit (C6, then C7, then C8): same goal shape as row C |

**Roster:**
- **lead:** dispatcher only. It fires sessions, reads notify-back summaries and CI status, and records operator decisions. It writes no code.
- **Implementer sessions:** U-A, U-B1, U-B2, U-B3, U-B4, U-B5, U-B6, U-B7, U-C1, U-C2. Ownership and sizes are in Section 6.
- **Background subagents:** research only, if needed (for example, re-grepping callers before C2/C5). They make no code changes.
- **Round 2 sessions:** U-A2 (A.3), U-B8 (install.sh, Section 3 B8), U-B9 (help metadata and presentation tests, Section 3 B9), U-C3 (C6, C7). The round-1 U-A is called U-A1 from here on. Ownership and sizes are in Section 6 (Round 2 tables).
- **Round 2b sessions:** U-B10 (install.sh failure copy, next steps, receipts) and U-B11 (install.sh `--json`). U-B8 keeps the safety core and U-C3 gains C8. Ownership and sizes are in Section 6.4.

**Task dependency graph:**
```
U-A ──► {U-B2, U-B3, U-B4, U-B5, U-B6} ──► U-B7 ──► [operator decisions C1,C3] ──► U-C1 (C1 → C4 → C3)
   └──► U-B1 (merge after U-B3) ─────────┘                                         │
                                          [operator decisions C2,C5] ──► U-C2 (C2 → C5 → 0.3.0 release commit)
```

**Round 2 dependency graph** (replaces the one above where they differ; Wave B now lands on the integration branch `cli-bp/wh-wave-b`, see Landing flow item 7):
```
U-A1 ──► U-A2 ──► {U-B2, U-B3, U-B4, U-B5, U-B6, U-B8} ──► U-B7 ──► U-B9 ──► PR cli-bp/wh-wave-b → main
              └──► U-B1 (merge after U-B3) ──────────────┘
main ──► [decisions C1,C3] ──► U-C1 (C1 → C4 → C3) ──► [decisions D-R2-4] ──► U-C3 (C6 → C7)
                                                   ──► [decisions C2,C5] ──► U-C2 (C2 → C5 → 0.3.0 release commit, after U-C3)
```

**Round 2b dependency graph** (replaces the install.sh path above; everything else is unchanged):
```
U-A2 ──► U-B8 ──► U-B10 ──► U-B11 ──┐
U-A2 ──► {U-B2..U-B6}, U-B1 after U-B3 ─┴──► U-B7 ──► U-B9 ──► PR cli-bp/wh-wave-b → main
main ──► U-C1 ──► [decisions D-R2-4, D-R2-12] ──► U-C3 (C6 → C7 → C8) ──► U-C2 (… release commit)
```

**Worktree assignments:** one worktree and branch per unit, each cut from `main` after its predecessors merge. Branches: `cli-bp/wh-a-shared`, `cli-bp/wh-b1-dispatcher`, `cli-bp/wh-b2-gc`, `cli-bp/wh-b3-status`, `cli-bp/wh-b4-new-launch`, `cli-bp/wh-b5-merge-init`, `cli-bp/wh-b6-config-doctor`, `cli-bp/wh-b7-docs`, `cli-bp/wh-c1-exit-status`, `cli-bp/wh-c2-consent-fetch`. Never use the main checkout `/Users/chrisren/Development/worktree-harness`; it is clean on `main`.
Round 2 branches: `cli-bp/wh-a2-shared`, `cli-bp/wh-b8-install`, `cli-bp/wh-b9-help-meta`, `cli-bp/wh-c3-install-contract`, plus the integration branch `cli-bp/wh-wave-b` (cut from `main` after U-A2 merges). Wave B unit branches are cut from, and merge into, `cli-bp/wh-wave-b` instead of `main`.
Round 2b branches: `cli-bp/wh-b10-install-report` and `cli-bp/wh-b11-install-json`. Each is cut from `cli-bp/wh-wave-b` only after its predecessor has merged there, because U-B8, U-B10 and U-B11 edit the same file.

**Spawn order:**
1. Fire U-A. When it merges, fire U-B1..U-B6 together; U-B1 holds its merge until U-B3 has merged.
2. When all six have merged, fire U-B7.
3. Ask the operator the four DECISION questions (C1, C2, C3, C5).
4. Fire U-C1 with the C1/C3 answers. After it merges, fire U-C2 with the C2/C5 answers.
5. (Round 2) Fire U-A2 when U-A1 merges; Wave B starts after U-A2. Fire U-B8 together with U-B1..U-B6. Fire U-B9 after U-B7. Open the single Wave B PR to `main` after U-B9 (Landing flow item 7).
6. (Round 2) Ask the Round 2 decisions (Section 7) together with step 3. U-B1, U-B8 and U-B9 need D-R2-1, D-R2-2, D-R2-3, D-R2-5, D-R2-6, D-R2-7, D-R2-8 and D-R2-9 before they fire; each has a recommended default the lead may apply if the operator defers.
7. (Round 2) Fire U-C3 after U-C1 merges and D-R2-4 is answered. U-C2's release commit waits for U-C3.
8. (Round 2b) Fire U-B8 as in step 5, U-B10 when it merges, and U-B11 when U-B10 merges. U-B7 now waits for U-B11. Ask D-R2-12 to D-R2-19 (Section 8) with step 6. U-B8 needs the amended D-R2-2, U-B10 needs D-R2-13 and D-R2-14, U-B11 needs D-R2-15, U-B3 needs D-R2-16, and U-C3 needs D-R2-12 for C8. The lead may apply each recommendation if the operator defers.

**Lead context budget and succession:**
- The lead holds this plan plus one short summary per fired session: about 11 summaries, roughly 15–25k tokens in total (estimated at ~1–2k per summary).
- **Succession point:** after U-B7 merges, before Wave C. Hand off to a fresh lead with this plan path, the merged SHAs and the operator's recorded decisions. Wave C then starts on a clean budget.
- **Round 2:** 15 sessions in total (about 22–38k tokens of summaries, estimated at the same ~1.5–2.5k per summary). The succession point moves to after the Wave B PR (U-B9) merges.
- **Round 2b:** 17 sessions in total, 16 implementers plus the lead (about 26–43k tokens of summaries, estimated at the same ~1.5–2.5k per summary). The succession point does not move.

## 1. Header

| Item | Value |
|---|---|
| Repo | `/Users/chrisren/Development/worktree-harness` (github.com/renchris/worktree-harness), branch `main` @ `b586f99`, version `0.2.0` (`lib/common.sh:12`) |
| CLIs covered | `bin/worktree-harness` and everything it sources: `lib/common.sh`, `compat.sh`, `config.sh`, `pm.sh`, `cmd_{new,launch,merge,gc,status,init,doctor}.sh`. `share/shell/*` and `share/completions/*` are only touched where a caller or a completion list must change. |
| Inputs | 21 kept findings and 1 dropped finding (verified JSON); `/tmp/cli-bp/checklist.md`; `/tmp/cli-bp/guidelines.md` |
| Repo rules read | No `CLAUDE.md` and no `.claude/` directory in this repo (measured: `ls CLAUDE.md .claude` reports "No such file"). The binding rules are in `CONTRIBUTING.md` and `.github/PULL_REQUEST_TEMPLATE.md`. **Constraints:** git + bash only, no new runtime dependency, and **bash 3.2-safe**, so no `declare -A`, `mapfile`/`readarray`, `[[ -v ]]`, `${x^^}` (guarded by `test/bashism.bats`). Fail closed, never silently. Conventional Commits in lowercase with no redundant verbs. Update docs (README / docs / `init` template) whenever behaviour or config changes. The operator's global CLAUDE.md was not visible to this worker (omitClaudeMd), so follow the operator's standard landing rules on top of this table. |
| Dirty files | **None.** Measured: `git -C /Users/chrisren/Development/worktree-harness status --porcelain` printed nothing. `git worktree list` shows only the main checkout. Do not edit the main checkout directly; each unit works in its own worktree or branch. |
| Planning probes | Measured on `/bin/bash` 3.2.57 with the toy `/tmp/cli-bp/wh_plan_probe.sh`; the audited CLI was not run. (1) `printf -v` from a callee sets the caller's `local`. (2) An unguarded `"${arr[@]}"` on an empty array under `set -u` fails with `x[@]: unbound variable`. The guarded `${arr[@]+"${arr[@]}"}` works. (3) `printf %q` escapes spaces. |
| CLIs covered (round 2) | Adds `install.sh` (POSIX sh, 54 lines, measured with `wc -l`; the `curl \| sh` entry point, unaudited in round 1 per critic2 `uncoveredClis[5]`). Its 15 verified findings are F22–F36. |
| Inputs (round 2) | 15 verified install.sh findings (JSON in the round-2 brief); every worktree-harness entry in `/tmp/cli-bp/critic2.json` (`missedFindings[6,7,8,11]`, `uncoveredClis[5]`, `planConflicts[3]`, `unmentionedRules[4,5,6,7,8,9,10,11,12,13,15,21,22,24,27,28,31,32,37,39,40,42,43]`). Each was re-checked by static reading at `main` @ `b586f99` (`git log -1`, measured); nothing under audit was executed. |
| Repo gate conflict (round 2) | `CONTRIBUTING.md:33-34` and `.github/PULL_REQUEST_TEMPLATE.md:11` require docs updated **in the PR** that changes behaviour. Round 1 deferred every docs edit to U-B7, so each B1–B6 PR to `main` would have failed that checklist item. Resolved by landing Wave B on an integration branch (Landing flow item 7). Alternative recorded as D-R2-10. |
| CLIs covered (round 2b) | No new CLI. A second audit of `install.sh` produced 18 verified findings, F41–F58. 14 merge into existing F22–F36 items and 4 are new work (F50, F53, F56, F58). |
| Inputs (round 2b) | The 18 findings (JSON in this round's brief), each re-read against `install.sh` at `b586f99` (`git log -1`, measured). Every worktree-harness entry in `critic2.json` was re-verified, including the generic entries round 2 did not list (Section 5). Nothing under audit was executed. `shellcheck -s sh install.sh` and `sh -n install.sh` both exit 0 (measured; both only parse the file). The repo still has no `CLAUDE.md`, `.claude/` or `package.json` (measured with `ls -a`), so no `node_modules` or similar gate exists to preserve. |
| Caller correction (round 2b) | The Homebrew formula's test is not `--version` only. `Formula/worktree-harness.rb:36` asserts `worktree-harness #{version}`, and `:40` runs `worktree-harness -C <testpath> init` (read from `~/Development/homebrew-tap` @ `24465d7`). Landing flow item 6, B1-7 and C6 said otherwise and now carry corrections. Effects: `-C` can't be removed without changing the formula first (D-R2-1), and `--version` keeps its `worktree-harness <v>` bytes (D-R2-17). |

### Finding index (the F-numbers used below; "verdict" is the verifier's refined contract)

| F | Finding (short) | Sev | Verdict | Plan placement |
|---|---|---|---|---|
| F1 | gc ignores --dry-run with --prune | high | compatible | B2 |
| F2 | new/launch dry runs mutate, claim success; launch --dry-run always fails | med | compatible | B4 (+B6 fetch) |
| F3 | usage errors exit 1/64, no help pointer, full-usage dump | high | breaking | B1/B2–B6 route through `wh_usage_die`; exit flip in C1 |
| F4 | merge conflict exits 2; doctor exit = issue count | med | compatible | C1 (coupled to F3) |
| F5 | outside a repo: silent 128; merge late git failures unreported | med | compatible | A (`wh_require_repo`), B2/B3/B4/B5 |
| F6 | gc --prune has no consent / --yes; --force synonym | med | breaking | B2 (--force warning), C2 |
| F7 | gc failed removal exits 0, hides git's reason | med | compatible | B2 |
| F8 | failed gc gates read as safe; status shows 0 for unknown; default-branch guess | med | breaking | B2/B3 (compatible parts), C3 |
| F9 | help on stderr, `help <cmd>` broken, help incomplete, >80 cols | med | compatible | B1, plus usage funcs in B2–B6 |
| F10 | --no-color no-op, stdout colour from stderr TTY, FORCE_COLOR/TERM ignored | med | compatible | A, B3 |
| F11 | status: padded piped table, footer on stdout, no --json | med | compatible | B3 (--json, plural), C4 (piped TSV, footer stream) |
| F12 | merge stdout carries git output; merge/gc/init print no identifier | low | compatible | B2, B5 |
| F13 | provisioning failures unchecked in `$(...)`; no trap | med | compatible | A (trap), B4 |
| F14 | unbounded fetch; origin fallback; invalid config accepted | med | breaking | B6 (bounded, warn), C5 |
| F15 | hand-rolled parsing: extra args ignored, globals only before the command | low | compatible | A (`wh_parse_opts`), adopted in B1–B6 |
| F16 | undocumented aliases with no warning | low | compatible | B1, B2 |
| F17 | next-step copy: unquoted paths, `#` comments, backticks, `(s)` | low | compatible | B1, B2, B4, B5, B6, B7 |
| F18 | non-atomic writes; 0600 applied after copy | low | compatible | A, B4, B5 |
| F19 | port offsets collide after gc | low | compatible | B4 |
| F20 | commit subjects not sanitized | low | compatible | A, B5 |
| F21 | doctor hides .harnessrc error line, skips GC_IDLE_MIN; wh_confirm default-yes | low | compatible | A, B6 |
| F22 | install.sh reads no argv: `--help`/typos run the full destructive reinstall | high | compatible | B8-1 |
| F23 | `curl \| sh` installs whatever `$PWD/bin/worktree-harness` is; source never shown | high | compatible | B8-2 |
| F24 | `rm -rf $SHARE_DIR` can delete the source (cwd = install dir, checkout in prefix) | high | compatible | B8-3 |
| F25 | non-atomic replace, no trap: failure/Ctrl+C leaves no install, leaks temp dir | med | compatible | B8-4 |
| F26 | overwrites an unmarked `$SHARE_DIR` and a foreign `$BIN_DIR/worktree-harness` | med | breaking | C7 (DECISION D-R2-4) |
| F27 | relative `WORKTREE_HARNESS_PREFIX` installs a dangling link and reports success | med | compatible | B8-5 (+D-R2-7) |
| F28 | clone failure silent (exit 128), may prompt for credentials, unbounded | med | compatible | B8-6 (R2b: copy in B10-1; exit code and prompt default in C8, per F44) |
| F29 | stdout carries progress, receipt and tips; no capturable result | med | breaking | C6 |
| F30 | next steps are not exact working commands | med | compatible | B8-8 |
| F31 | optional offers always shown; no guidance-off switch | low | compatible | B8-9 (+D-R2-5, D-R2-8) |
| F32 | receipt has no version/commit; installs mutable `main` with no pin | low | compatible | B8-10 |
| F33 | `WORKTREE_HARNESS_REPO` undocumented; URL (maybe with credentials) echoed | low | compatible | B8-7 |
| F34 | glyph/copy style: `→` progress, lowercase colon label, no ASCII fallback | low | compatible | B8-11 (+D-R2-6) |
| F35 | no uninstall command; README uninstall prose ignores the prefix | low | compatible | B8-12, B7 |
| F36 | installer has only a happy-path CI smoke | low | compatible | B8-13 |
| F37 | gc prints only `basename`; no output names a removed path (critic `missedFindings[6]`, R212/R191) | med | compatible | B2-8 |
| F38 | `-C` and `-V` are outside the short-option table; A.1 spread `-C` to every command (critic `missedFindings[7]`, R466/R062) | low | compatible (`--cwd`/`-v` added; any `-C`/`-V` removal is a later major) | A.3-1, A.3-2, B1-7, B7 (+D-R2-1) |
| F39 | gc label case/colons inconsistent (`skip` vs `KEEP`, `Remaining worktrees:`) (critic `missedFindings[8]`) | low | compatible | B2-9 |
| F40 | plan adds help examples with no parser test (critic `missedFindings[11]`, R100) | med | compatible | A.3-6, every B unit, B8-1, B9 |
| F41 | `install.sh --help` runs the full install; unknown arguments are ignored. Adds: help must win over earlier tokens, a `help` arm, empty `--prefix=` | high | compatible | merges F22: B8-15 (+D-R2-2, D-R2-3) |
| F42 | `rm -rf` and `ln -sf` run with no preview, refusal or consent. Adds: per-path recognition, `--force` still needs `--yes` and `--prefix` | med (verifier; finder said high) | breaking (foreign-target branch only) | merges F24, F26: C7 R2b (+D-R2-4) |
| F43 | existing install destroyed before the source is validated; swap not atomic. Adds: fresh-prefix `mkdir`, stage mode, reverse overlap | high | compatible | merges F24, F25: B8-17 |
| F44 | `git clone` failure silent, unbounded, exits 128 | high | breaking (narrow: 128 → 1, typed credentials off) | merges F28, F33: B10-1 (copy), C8 (exit code, prompt default) |
| F45 | install source guessed from the cwd under `curl \| sh`, never named | med | compatible | merges F23: B8-2 correction |
| F46 | environment values not validated: relative prefix, quoted `~`, dash-leading URL | med | compatible (`~` rejection needs a decision) | merges F27: B8-5, B8-19, C8 (+D-R2-12) |
| F47 | all status text on stdout, no bare identifier, a closed pipe can abort the install | med | breaking (stream move only) | merges F29: B10-5 (closed streams), C6 R2b (stream move) |
| F48 | next steps are prose, unchecked against state, always printed | med | breaking (stream part only, already in C6) | merges F30, F31: B10-3 (+D-R2-13) |
| F49 | status copy uses off-spec glyphs with no plain fallback | low | compatible | merges F34: B8-11 correction |
| F50 | failures surface as raw tool errors with no action, cause or recovery | med | compatible | **new**: B10-2 |
| F51 | no signal or exit trap: temp clones leak, an interrupted install is unreported | med | compatible | merges F25: B8-18 |
| F52 | receipt doesn't distinguish fresh, replaced or unchanged, and names no version | low | compatible | merges F32: B10-4 (+D-R2-14); C7's receipt bullet moves here |
| F53 | installer has no `--json` | low | compatible | **new**: B11 (+D-R2-15) |
| F54 | install environment variables incompletely documented | low | compatible | merges F33: B8-7, B7 R2b |
| F55 | `WORKTREE_HARNESS_REPO` echoed with credentials; the planned sed leaks part of a password | low | compatible | merges F33: B8-7 correction |
| F56 | a truncated `curl \| sh` download can run a partial script | low | compatible | **new**: B8-16 |
| F57 | installer has no behaviour tests and is outside the shellcheck gate | low | compatible | merges F36: B8-13, B8-14 corrections, B8-20 |
| F58 | threat model's network and write claims omit the installer's clone and temp dir | low | compatible | **new**: B7 R2b (+D-R2-19) |

### Gates (exact commands; run from the unit's worktree root)

```sh
shellcheck bin/worktree-harness lib/*.sh share/shell/bash.sh          # CI pins shellcheck v0.11.0 (local: 0.11.0, measured)
bats test/                                                            # local bats 1.13.0 (measured)
PATH="/bin:/usr/bin:/sbin:/usr/sbin:$(dirname "$(command -v bats)")" bats test/   # macOS: re-run on system bash 3.2, mirrors ci.yml
p="$(mktemp -d)"; WORKTREE_HARNESS_PREFIX="$p/prefix" sh ./install.sh && "$p/prefix/bin/worktree-harness" --version   # install smoke, mirrors ci.yml
```
`test/bashism.bats` runs inside `bats test/` and covers the bash-3.2 grep guard, `bash -n` on every script, and the parse of all three completion files.

New test files that use `run --separate-stderr` must put `bats_require_minimum_version 1.5.0` at the top of the file. CI clones bats-core HEAD and the local copy is 1.13.0, so both support it.

**Round 2 gates (added; none of the four above is dropped).** `install.sh` is POSIX sh and is not in the shellcheck list or `test/bashism.bats` today (measured: `ci.yml:23`, `test/bashism.bats:27`). From U-B8 on, every unit also runs:
```sh
shellcheck -s sh install.sh                                           # U-B8 adds it as its own CI step beside ci.yml:23, and to CONTRIBUTING.md:21/:30 and the PR template :7 (R2b: never in the ci.yml:23 list; see B8-20)
sh -n install.sh && { ! command -v dash >/dev/null || dash -n install.sh; }   # also asserted inside test/install.bats
p="$(mktemp -d)"; WORKTREE_HARNESS_PREFIX="$p/p2" sh ./install.sh --help >/dev/null && [ ! -e "$p/p2" ]   # help does no work (U-B8 adds this to the ci.yml install job)
```

### Landing flow

1. One branch and worktree per implementer unit (Section 6). Commit messages are Conventional Commits: `fix(gc): honor --dry-run with --prune`, `feat(status): --json`, and so on.
2. Every commit passes all four gates, with a bats test covering the change (PR template checklist).
3. Open a PR to `main` on renchris/worktree-harness. CI (`ci.yml`) must be green on ubuntu and macOS, including the `/bin/bash` 3.2 re-run and the install smoke.
4. Waves land in order: **A, then B, then C.** Wave B units are file-disjoint and can be developed in parallel. B1 merges after B3 because root help advertises `status --json`. B7 (docs) merges last in Wave B.
5. Wave C runs as **serialized commits**. Each commit updates its callers (tests, SKILL/README, completions) in the same commit and adds a CHANGELOG `[Unreleased]` entry. Items marked **DECISION** wait for the operator.
6. The release carrying Wave C is **0.3.0**. Under SemVer 0.x, a minor bump is the major-equivalent R386 requires. Bump `WH_VERSION` (`lib/common.sh:12`) and the CHANGELOG heading in the release commit. The Homebrew tap formula (`renchris/homebrew-tap`, separate repo) is out of scope here; its test uses only `--version`. **R2b correction:** its test also runs `worktree-harness -C <testpath> init` (`Formula/worktree-harness.rb:40`) and asserts the `worktree-harness <v>` bytes (`:36`). Nothing in this plan breaks either before a later major, but the release checklist must run `brew test` against the 0.3.0 tree.
7. **(Round 2) Docs gate.** The repo's PR checklist (`CONTRIBUTING.md:33-34`, `PULL_REQUEST_TEMPLATE.md:11`) wins over round 1's "docs in B7" ordering. Wave B units open their PRs against `cli-bp/wh-wave-b`; CI still runs on each, because `ci.yml:6` triggers on every `pull_request`. One PR from `cli-bp/wh-wave-b` to `main` opens after U-B9 merges, so the PR that reaches `main` carries code and docs together. Wave A (no behaviour or doc change) and each Wave C commit (callers and docs in the same commit) already satisfy the gate. D-R2-10 records the per-PR-docs alternative.
8. **(Round 2) Wave B order.** U-B1..U-B6 and U-B8 run in parallel. U-B7 (docs) merges after all seven; U-B9 merges last because its drift tests read U-B7's completions and every unit's final help text.
9. **(Round 2b) install.sh order.** U-B8, U-B10 and U-B11 edit one file, so they run serially on `cli-bp/wh-wave-b`, and each fires when its predecessor has merged. Their test files are disjoint (`test/install.bats`, `test/install_output.bats`, `test/install_json.bats`). U-B7 merges after U-B11.

---

## 2. Wave A: shared helper (`lib/common.sh`)

**Why one module.** Findings F1, F3, F6, F9, F10, F11, F12, F13, F15, F17, F18, F20 and F21 share six root causes:
- no shared argument parser;
- no usage-error exit path;
- colour decided once at source time, on the wrong stream;
- no consent helper (and `wh_confirm` defaults quietly);
- no atomic write;
- no signal trap.

The guide's "Enforce the rules in shared code" (R408–R418) puts these in one module. Wave A adds them to `lib/common.sh` and changes **no exit code and no stdout contract**. Commands adopt the helpers in Wave B.

**Unit U-A owns:** `lib/common.sh`, `test/common.bats` (new), `test/helper.bash`, and a two-line hook in `bin/worktree-harness` after line 79.

### A.1 API (bash 3.2-safe; ~190 LOC source, estimated by counting each helper's body below)

```bash
# --- exit codes (Reference L) -------------------------------------------------
WH_EXIT_USAGE=1            # Wave C1 flips this to 2, together with bin:137 and merge:78, in ONE commit
WH_EXIT_MISSING_INPUT=2    # used only by NEW paths (gc confirmation_required in C2)

wh_usage_die <cmd-or-""> <message> [<reason>=invalid_arguments]
#   stderr (R2, R105/R084 and the guide's usage-error exemplar; round 1 had "See: worktree-harness [<cmd> ]--help" on one line):
#     "<Error:|✗> <message>", a blank line, "See all options:", then "    worktree-harness [<cmd> ]--help" on its own line
#   exit "$WH_EXIT_USAGE". With WH_JSON=1 it writes one JSON error line instead (A.3-7).

wh_parse_opts <cmd> <max-positionals|rest> "<spec>" -- "$@"
#   spec: space-separated entries "a|b=VAR" (boolean: VAR=1) or "a|b=VAR:" (takes a value: --a v | --a=v)
#   built in for every command:
#     -h|--help        prescan argv up to "--"; if present call _wh_<cmd>_usage (stdout) and exit 0 (R083: help wins)
#     --dry-run        WH_DRY_RUN=1; export
#     --no-color       WH_NO_COLOR=1; export; wh_init_style
#     -C <dir>|-C=<dir> cd now (runs before any wh_load_config / repo lookup) (R066: globals after the command)
#       R2 (R466/R062, F38): the canonical built-in is "--cwd <DIR>|--cwd=<DIR>"; "-C" stays accepted only as the
#       compatibility spelling decided in D-R2-1 and is never shown in help or completions. See A.3-1.
#     -v|--version     R2 (R086/R066): print "worktree-harness $WH_VERSION" on stdout, exit 0; --help wins. See A.3-2.
#   "--" ends options. In "rest" mode the first positional, or anything after "--", goes to WH_ARGS verbatim (launch).
#   result: WH_ARGS=( positionals ). Callers read it as ${WH_ARGS[@]+"${WH_ARGS[@]}"} or "${WH_ARGS[0]:-}"
#   errors, all through wh_usage_die <cmd>:
#     "Unknown option <x> for worktree-harness <cmd>."  "Unexpected argument <x> for worktree-harness <cmd>."
#     "Option <x> needs a value."  "Option <x> doesn't take a value."
#   implementation: plain for-loop over $spec, case "|$names|" in *"|$name|"*; printf -v "$var" (bash >= 3.1).
#   No associative arrays.

wh_init_style
#   stderr roles: WH_C_{RED,GREEN,YELLOW,BLUE,DIM,BOLD,RESET}; stdout roles: WH_O_{DIM,RESET}; WH_RICH_ERR=0|1
#   WH_TTY_OUT=0|1, WH_TTY_ERR=0|1  (R408: the only [ -t N ] checks in the codebase live here and in wh_require_consent)
#   per-stream colour precedence (R206): WH_NO_COLOR=1 (--no-color) > non-empty NO_COLOR > FORCE_COLOR
#     (set and != 0 -> on, 0 -> off) > [ -t N ] && TERM != dumb.  Rich glyphs (R115): [ -t 2 ] && TERM != dumb.
#   Called at source time (keeps today's behaviour) AND again after global flags (hook below).
# Glyphs (R182/R186/R205): rich -> wh_ok "✓", wh_step "→", wh_warn "!", wh_err "✗"
#                          plain -> wh_ok/wh_step no glyph, wh_warn "Warning: ", wh_err "Error: "
#   R2 (R182: progress has a blank gutter; F34 verdict): rich wh_step prints two spaces, not "→". Progress copy is a
#   present participle ending in "…" (rich) or "..." (plain) (R220/R205). D-R2-6 records keeping "→" as the alternative.

wh_plural <n> <one> <many>          # "1 worktree" / "3 worktrees"   (R217)
wh_sanitize_stream                  # stdin->stdout: LC_ALL=C tr -d '\000-\010\013-\037\177' | LC_ALL=C sed $'s/\xc2[\x80-\x9f]//g'
                                    #   (strips C0 except \t \n, DEL, and UTF-8 C1; never byte-level \200-\237) (R359)
wh_json_str <s>                     # JSON string literal: \\ \" \t \n \r and other C0 as \u00XX  (R410 shared writer)
wh_require_repo <cmd>               # git rev-parse --show-toplevel >/dev/null 2>&1 || wh_die "Can't run worktree-harness <cmd>
                                    #   outside a git repository. cd into your repo (or pass -C <repo>) and re-run."  (R275)
                                    #   R2 (R099: printed commands use long options): "(or pass --cwd <DIR>)". In JSON mode the
                                    #   reason is repository_not_found (A.3-7).
                                    #   Deliberately NOT inside wh_load_config: launch must keep working outside a repo.
wh_require_consent <question> <missing-headline> <rerun-cmd> <assume_yes:0|1>    (R146/R409/R413; replaces wh_confirm)
#   assume_yes=1 -> return 0
#   stdin AND stderr are TTYs and CI is unset -> prompt "? <question> (y/N) "; y -> 0; else "Canceled." exit 130
#   otherwise -> wh_err "<missing-headline>" (e.g. "Can't remove worktrees without --yes in non-interactive mode.")
#                wh_info "  <rerun-cmd>"; exit "$WH_EXIT_MISSING_INPUT"   (confirmation_required, Reference J)
wh_atomic_write <target> [mode]     # stdin -> mktemp "$dir/.<base>.XXXXXX" -> chmod mode (default: 0666 & ~umask,
                                    #   because mktemp creates 0600) -> mv -f  (R351)
wh_write_new <target> [mode]        # same, but publishes with `ln tmp target` (fails if target exists, so no clobber race),
                                    #   then rm tmp; returns 1 if target exists (R350/R351)
WH_PARTIAL_PATH=""; WH_PARTIAL_BRANCH=""          # set by a command while it holds partial state
wh_install_signal_traps                           # ONE root trap (R416): INT->130, TERM->143, HUP->129
_wh_on_signal <SIG> <code>                        # trap - SIG; if [ -e "$WH_PARTIAL_PATH" ]: "Stopped. Partial worktree
                                                  #   left at <path> (branch <b>). To remove it:" + the two commands; exit <code>
```
Delete `wh_confirm` (`lib/common.sh:32-41`; it has no callers, measured with `grep -rn wh_confirm`). Its non-TTY default-yes is the latent R147 hazard in F21. Keep `wh_run`.

**Hook in `bin/worktree-harness`** (2 lines, after line 79): call `wh_init_style` (fixes F10's `--no-color` no-op at bin:70) and `wh_install_signal_traps` (F13). Signal traps do not reach `$(...)` subshells. Wave B4 therefore removes the command substitution around `wh_create_worktree`.

**`test/helper.bash` additions:** `make_norepo()`, which runs `mkdir "$BATS_TEST_TMPDIR/norepo"; cd` into it and exports `GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"` so git never finds an enclosing repo.

### A.2 Tests: `test/common.bats` (new, ~110 LOC; source `lib/common.sh` directly)

| Test name | Assertion |
|---|---|
| `usage die exits WH_EXIT_USAGE and names the help command` | `run bash -c '. lib/common.sh; wh_usage_die gc "Unknown option --x for worktree-harness gc."'` gives `status -eq 1` and output containing `See: worktree-harness gc --help` (R2: assert `*"See all options:"*` and a line equal to `    worktree-harness gc --help`, per the A.1 layout fix) |
| `parse_opts rejects an unknown option` / `... an extra positional` | non-zero; `*"Unknown option --bogus for worktree-harness gc."*` / `*"Unexpected argument junk"*` |
| `parse_opts accepts --opt=value and stops at --` | spec `--name=v:`: `--name=x` gives `v=x`; `-- --name` leaves `--name` in WH_ARGS |
| `parse_opts rest mode passes the command through untouched` | `launch rest "" -- claude --resume` gives WH_ARGS=(claude --resume) |
| `parse_opts help wins over a bad option and prints to stdout` | `run --separate-stderr ... gc --bogus --help`: status 0, usage on `$output`, `$stderr` empty |
| `parse_opts -C after the command changes directory` | `pwd` after parse equals the target dir |
| `init_style precedence` (4 cases) | `FORCE_COLOR=1` gives non-empty `WH_C_RED`; `+ WH_NO_COLOR=1` gives empty; `NO_COLOR=1 FORCE_COLOR=1` gives empty; `FORCE_COLOR=0` gives empty |
| `plain stderr uses Warning:/Error: prefixes` | `wh_warn x` gives `Warning: x`; `wh_err y` gives `Error: y` (bats stderr is not a TTY) |
| `plural picks singular for 1` | `1 worktree`, `2 worktrees` |
| `sanitize strips ESC and C1 but keeps UTF-8` | `printf 'caf\xc3\xa9 \033[31mred\xc2\x9b\n' \| wh_sanitize_stream` gives `café [31mred` |
| `json_str escapes quotes, backslashes, tabs, newlines` | exact string compare |
| `require_consent fails with exit 2 and names --yes when stdin is not a TTY` | `</dev/null`: status 2; output has the headline and the rerun command |
| `atomic_write leaves no temp file and keeps umask mode` / `write_new refuses an existing file` | no `.x.*` siblings; mode `-rw-r--r--` under umask 022; second `wh_write_new` returns 1 and the content is unchanged |
| `signal trap names the partial worktree and exits 143 on TERM` | a `bash` that sources common.sh, sets `WH_PARTIAL_PATH` to an existing dir, installs the traps and runs `kill -TERM $$` exits 143; output contains the path |
| `--no-color disables color (CLI)` | `FORCE_COLOR=1 run "$WH" --no-color definitely-not-a-command`: output has no `$'\033'`; without `--no-color` it has one (proves the flag now works) |

**Wave A size:** ~300 LOC (~190 source, ~110 tests). Estimated per helper, from the line counts of the existing equivalents in `common.sh` and `cmd_*.sh`.

### A.3 Round 2 additions (unit U-A2, after U-A1; owns `lib/common.sh`, `test/common.bats`, `test/helper.bash`)

U-A1 is already near its size budget (~300 LOC), so these land as a second serial unit on the same files. Like A.1, A.3 changes **no exit code and no stdout contract**.

| # | Rules | Site | Change | Callers |
|---|---|---|---|---|
| 1 | R466 R062 R066 R099 R385 (F38) | `wh_parse_opts` built-ins (A.1) | `--cwd <DIR>` / `--cwd=<DIR>` is the canonical working-directory option. `-C <DIR>` / `-C=<DIR>` behaves identically; under D-R2-1 (a) it also calls `wh_deprecated cwd "-C" "--cwd"`. A missing value says `Option --cwd needs a value.` (or `-C` when that spelling was used). | `test/gc.bats:9,19,29,40,51,58` pass `-C "$APP"` before the command (bin's loop, B1-7) and keep working; README.md:245 and `share/completions/worktree-harness.bash:12,20` move to `--cwd` in B7. |
| 2 | R086 R066 R392 | `wh_parse_opts` built-ins | `-v`/`--version` at any depth prints `worktree-harness $WH_VERSION` on stdout, exit 0. `--help` wins when both are present. With `--json` also present it prints `{"version":"<v>"}`. | `ci.yml:61` and `test/dispatcher.bats:5` use root `--version` (unchanged bytes). |
| 3 | R308 R050 R385 (critic `unmentionedRules[31]`) | new `wh_deprecated <id> <old> <new>` | Prints `Warning: '<old>' is deprecated. Use '<new>'.` (plain) or `! …` (rich) at most once per `<id>` per run. Tracks seen IDs in a space-padded string (`case " $WH_DEPRECATED_SEEN " in *" $id "*`; no associative arrays). | B1-6 (aliases), B2-1 (`gc --force`), A.3-1 and B1-7 (if D-R2-1 deprecates `-C`/`-V`) call it instead of a raw `wh_warn`. |
| 4 | R087 R090 | `wh_parse_opts` help prescan | When `--help` is present and `declare -F _wh_help_json` succeeds and `--json` is also present, call `_wh_help_json <cmd>` (defined by U-B9) instead of the human usage. Before U-B9, `<cmd> --help --json` prints human help. | U-B9 |
| 5 | R182 R205 R220 (F34 verdict) | `wh_step` | Blank rich gutter, per the A.1 R2 note. Existing `wh_step` messages (`lib/*.sh`, 10 call sites, measured with `grep -c wh_step`) are rewritten as present participles with `…`/`...` by the unit that owns each file. | No test asserts a glyph (measured: `grep -n '→\|✓\|⚠\|✗' test/*.bats` matches only two comments). |
| 6 | R100 (F40, critic `missedFindings[11]`) | `wh_parse_opts`; `test/helper.bash` | **Parse-only hook:** when `__WH_PARSE_ONLY=1`, `wh_parse_opts` exits 0 right after a successful parse, before the command does any work. The variable is internal (Reference C `__<PREFIX>_*`) and never appears in help. **Helper** `assert_help_examples_parse <cmd>`: runs `"$WH" <cmd> --help`, takes every line under `Examples:` that starts with four spaces and `worktree-harness `, and substitutes `<BRANCH>`→`r2-example`, `<DIR>`→`$BATS_TEST_TMPDIR`, `<COMMAND>`→`true` and `<FIELDS>`→`branch,path`. It runs each line through `eval` with `__WH_PARSE_ONLY=1` set; the text is the CLI's own help, so this is trusted. It asserts status 0 for every line and at least one example when the help has an `Examples:` section. | Every B unit adds a one-line `every <cmd> --help example parses` test (B1–B6 rows below); U-B9 runs the same check over all metadata examples. |
| 7 | R243 R244 R251 R253 R255 R256 R261 R262 R264 R410 (critic `unmentionedRules[28]`) | new JSON mode in the shared writer | `WH_JSON=0\|1`. The help prescan sets it when `--json` is in argv before `--` and the spec declares `--json`, so usage errors are already in JSON form. When it is 1, `wh_info`/`wh_step`/`wh_ok`/`wh_warn` are no-ops (R244/R410). The new `wh_fail <exit> <reason> <message> [<next-command>]` writes the human error, or in JSON mode exactly one line on stderr: `{"status":"error","reason":"<r>","message":"<msg>"[,"next":[{"command":"…","argv":[…]}]]}` (R253/R256/R261). `wh_die` becomes `wh_fail 1 "${WH_FAIL_REASON:-internal_error}" "$*"`. `wh_usage_die` passes `unknown_option` or `invalid_arguments`. A single reason registry `WH_REASONS="invalid_arguments unknown_option unknown_command repository_not_found invalid_config conflict network_error partial_failure confirmation_required canceled internal_error"` (R255). `_wh_on_signal` in JSON mode writes `{"status":"error","reason":"canceled","message":"Canceled.","data":{"remote":"none"}}` and keeps 130/143/129 (R262/R336). **Result writer** `wh_json_out <compact-json>`: prints it as is when `WH_TTY_OUT=0`, and re-indents it with 2 spaces through a string-aware awk when `WH_TTY_OUT=1` (R251). | Only `status --json` (B3) uses JSON mode in Wave B. B6-8 passes `invalid_config`. |
| 8 | R238 R240 (critic `unmentionedRules[27]`, F31) | new `wh_guidance_enabled`, `wh_offer_enabled` | `wh_guidance_enabled`: true unless the guidance variable (name per D-R2-5; recommended `WH_GUIDANCE_DISABLED`) is non-empty. `wh_offer_enabled`: guidance enabled **and** `WH_TTY_ERR=1` **and** `CI` unset **and** `WH_JSON=0` (R240). Required recovery never checks either function. **R2b correction (R113, R010):** `wh_offer_enabled` also needs a stdin TTY, because stdin that isn't a TTY makes the run non-interactive. `wh_init_style` gains `WH_TTY_IN`, so the check stays in this module (R408). | B4-12 (next steps after `new`). install.sh carries its own POSIX copy (B8-9). |
| 9 | R068 R066 (R2b; contradicts A.1's `Option <x> doesn't take a value.`) | `wh_parse_opts` boolean entries | A boolean also accepts `--<name>=true`, `--<name>=false` and the negation `--no-<name>`, which set VAR to 1, 0 and 0. An entry already spelled `--no-<name>` (`--no-verify`) takes `--<name>` as its negation. Any other value gives `Option --<name> takes true or false.` through `wh_usage_die`. Help shows only the presence form. | No test passes `--x=value` today (measured: `grep -rnE -- '--(prune\|dry-run\|no-color\|no-verify)=' test` finds 0). B1-10 applies the same rule to bin's global loop. |
| 10 | R309 R312 R244 R249 R385 (R2b; contradicts A.3-7's no-op `wh_warn`) | A.3-3 `wh_deprecated`, A.3-7 `wh_warn`, `wh_json_out` | **Warnings are kept, not dropped.** In JSON mode `wh_warn` appends to `WH_JSON_WARNINGS` instead of doing nothing, and `wh_json_out` adds top-level `"warnings":[{"reason":"…","message":"…"}]` when any exist (R250). Reasons come from a registry `WH_WARNING_REASONS="deprecated general"` (R312). An error document stays one line with no warnings (R253). **Early warnings:** bin's global loop runs before the command's parser knows about `--json`, so `worktree-harness -C "$D" status --json` would print its deprecation on stderr and break R244. `wh_deprecated` therefore queues in `WH_PENDING_WARNINGS` until `wh_parse_opts` decides the mode; bin flushes the queue to stderr before dispatching a command with no parser (`help`, `version`). | B3 (`status --json`) is the only JSON command in Wave B. B9's `<cmd> --help --json` prints no warnings. |
| 11 | R173 R176 (R2b) | new `wh_print_id <value>` | Prints the value on stdout when stdout isn't a TTY or the run is non-interactive, so `x=$(…)` works. On an interactive TTY it prints nothing, because the receipt already shows the value (guidelines.md:549). | B2-10, B5-3 and B5-8 call it. `new` keeps printing its path unconditionally (README.md:100, SKILL.md:59; same bytes). Their tests run without a pty, so they still see the value. |
| 12 | R408 R116 (R2b) | `test/common.bats` | Add the lint R408 requires: `[ -t N ]` and `$CI` reads appear only in `lib/common.sh`. `lib/cmd_new.sh:81` exports `CI` to the install child, which is not a mode check (measured: `grep -nE '\[ -t [012] \]\|\$\{?CI\b' bin/worktree-harness lib/*.sh share/shell/*` finds only that line and `lib/common.sh:16`). install.sh is standalone and keeps its one check block (B8-11). | none |

A.2 tests appended (`test/common.bats`; `bats_require_minimum_version 1.5.0` is already required there):

| Test name | Assertion |
|---|---|
| `--cwd and -C change directory identically` (R392) | both spellings in `wh_parse_opts gc 0 "" -- --cwd "$D"` / `-C "$D"` leave `pwd` = `$D`. Repeated: `--cwd "$A" --cwd "$B"` ends in `$B` (last wins) |
| `a repeated boolean option is accepted once` (R392) | `wh_parse_opts gc 0 "--prune=prune" -- --prune --prune` gives status 0 and `prune=1` |
| `--version works after the command and --help wins` (R086) | `wh_parse_opts gc 0 "" -- --version` prints `worktree-harness 0.2.0` and exits 0; `-- --version --help` prints usage |
| `a deprecation prints once per run` (R308) | `bash -c '. lib/common.sh; wh_deprecated x old new; wh_deprecated x old new' 2>&1 \| grep -c deprecated` equals 1 |
| `parse-only exits 0 before the command body` (R100) | `__WH_PARSE_ONLY=1 bash -c '. lib/common.sh; wh_parse_opts gc 0 "--prune=prune" -- --prune; echo reached'`: status 0, output lacks `reached` |
| `JSON mode writes one error line and nothing on stdout` (R253/R261) | `run --separate-stderr bash -c '. lib/common.sh; WH_JSON=1; wh_info hi; wh_fail 1 invalid_config bad'`: status 1, `[ -z "$output" ]`, `$stderr` is exactly `{"status":"error","reason":"invalid_config","message":"bad"}` |
| `every wh_fail reason is in the registry` (R255) | `grep -rhoE 'wh_fail [0-9]+ [a-z_]+' lib bin` reasons ⊆ `$WH_REASONS` |
| `json_out compacts when piped` (R251) | piped output is one line; a pretty-print case on a pty via `script` is skipped when `script` is unavailable |
| `TERM=dumb on a TTY gives plain glyphs and no color` (R404/R115) | macOS `script -q /dev/null env -u FORCE_COLOR TERM=dumb bash -c '. lib/common.sh; wh_warn x'` (Linux `script -qec`): output has `Warning: x` and no `033`; skip without `script` |
| `INT exits 130 and names the partial worktree` (R398) | same harness as the TERM test, with `kill -INT $$` in a foreground `bash` (traps installed); status 130 |
| `guidance helper honors the disable variable` (R238) | `WH_GUIDANCE_DISABLED=1` makes `wh_guidance_enabled` false; empty or unset makes it true |
| R2b: `boolean options parse =true, =false and --no-` (R068) | `wh_parse_opts gc 0 "--prune=prune" -- --prune=false` gives `prune=0`; `--no-prune` gives `prune=0`; `--prune=maybe` exits non-zero with `*"takes true or false"*` |
| R2b: `warnings go in the JSON document` (R309, R244) | `run --separate-stderr bash -c '. lib/common.sh; WH_JSON=1; wh_deprecated x old new; wh_json_out "{\"a\":1}"'`: `[ -z "$stderr" ]`, `*'"warnings":[{"reason":"deprecated"'*` |
| R2b: `print_id is quiet on an interactive TTY` (R173) | piped: prints the value. On a pty via `script` with stdin, stdout and stderr all TTYs: prints nothing. Skip without `script` |
| R2b: `offers need a stdin TTY` (R113) | under `script`, `wh_offer_enabled </dev/null` is false and `wh_offer_enabled` alone is true. Skip without `script` |
| R2b: `only common.sh checks TTYs and CI` (R408) | `grep -nE '\[ -t [012] \]\|\$\{?CI\b' bin/worktree-harness lib/*.sh \| grep -v '^lib/common.sh:' \| grep -v 'export CI='` prints nothing |

**A.3 size:** ~85 source + ~95 tests = **~180 LOC** (estimated with the same per-helper and ~8–15 lines-per-case method as A.2). **R2b:** +~35 source, +~45 tests = **~260 LOC** (estimated, same method).

---

## 3. Wave B: compatible fixes, grouped by file owner

Rules for every Wave B unit:
- **No exit code changes on paths that are already non-zero.** Usage errors go through `wh_usage_die`, which still exits 1 until C1. bin:137 keeps `exit 64` until C1.
- **No stdout contract changes.** `new` still prints only the path, and `--porcelain` stays byte-identical.
- **Keep every substring the current tests match:** `"dirty"`, `"not in main"`, `"modified <"`, `"refusing to create a worktree on 'main'"`, `"you are ON 'main'"`, `"uncommitted changes"`, `"ancestry"`, `"unknown global flag"`, `"unknown command"`, `"HARNESS_BASE_POLICY"`, `"HARNESS_GC_IDLE_MIN"`, `"base policy   : "`, `"default branch: main"`, `"pnpm install --frozen-lockfile"`.
  - **R2 exception (R060, Reference J):** `"unknown global flag"` and `"unknown command"` are dropped from this list. Both messages become the guide's headlines, `Unknown option <x> for worktree-harness.` and `Unknown command <x> for worktree-harness.` (B1-4, B1-5). U-B1 owns `test/dispatcher.bats` and updates `:22` and `:28` in the same commit. This is a human-copy change (R383), so no migration is needed.
- **Help text:** usage functions print to **stdout** (R083). Lines stay at or under 80 columns (R095). Options are listed alphabetically (R089). Each subcommand help ends with `Global options: worktree-harness --help` (R090). Error paths no longer dump full usage; they use `wh_usage_die`, which prints one line plus a pointer.
- **R2 help rules for every usage function (R087 R091 R093 R098 R100 R101 R102 R231 R060 R473):**
  - Sections in this order, empty ones omitted: `Usage:` (`worktree-harness <cmd> <args> [options]`) followed directly by a one-line imperative summary; `Options:`; `Global Options:` (one-line pointer); `Examples:`; `Notes:`; `Learn more:`. Headings are Title Case and keep their colons. Never write "flag": say "option".
  - Placeholders are `<UPPER_CASE>` (`<BRANCH>`, `<DIR>`, `<COMMAND>`, `<FIELDS>`), and repetition is written `[<ARG>]...`. This retires `<branch>`, `<dir>`, `<cmd...>` and `[args...]`.
  - Each leaf help has 1–3 `Examples:` covering distinct jobs. Each is indented 4 spaces and runs one real action, never `[options]`. Each unit adds `every <cmd> --help example parses` (`assert_help_examples_parse <cmd>`, A.3-6).
  - Environment variables (`WH_NO_FETCH`, `WH_ISOLATION_SKIP`) go in the `Notes:` of the commands they affect, with their empty-value behaviour (R079). `HARNESS_*` names are `.harnessrc` settings, not environment variables: `wh_set_defaults` (config.sh:19-33) overwrites them, as verified for critic `unmentionedRules[9]`. Help must not present them as env vars.
- **No CHANGELOG/README/SKILL edits in B1–B6.** Each unit lists its CHANGELOG lines in its PR body and B7 writes them. (R2: these units and U-B8 merge into `cli-bp/wh-wave-b`, and B7 lands there before anything reaches `main`. See Landing flow item 7.)
- **R2b: the exit-code rule covers install.sh.** Round 2's B8-6 moved a failed clone from exit 128 to 1, which the first rule above forbids in Wave B, and F44's verifier labels that change breaking. It moves to C8. An unknown option or `--prefix=` is not covered by this rule: those inputs exit 0 and install today, no caller passes them, and exit 2 is their first contract (F41).

### B1: `bin/worktree-harness` + `test/dispatcher.bats` (append only; leave lines 19–23 for C1)

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R083 R081 R012 | bin:23-24, 71, 135 | `_wh_usage` prints to stdout (`cat <<'EOF'`). At the top of `main()`, **before** the lib lookup at :56, add `case "${1:-}" in -h\|--help\|help) [ $# -le 1 ] && { _wh_usage; return 0; };; esac`, so root help works without `lib/`. Move the dispatch `case` into `_wh_dispatch <cmd> "$@"`. `help <cmd>` becomes `_wh_dispatch "$cmd" --help`, and `help <unknown>` takes the unknown-command path. |
| 2 | R095 R023 R079 R090 | bin:28-49 | Wrap :36/:38/:39 (85/84/85 bytes, measured with `awk 'length>80'`). Make the gc line `gc [--prune] [--dry-run]` and the status line `status [--porcelain\|--json]`. Add an `ENVIRONMENT` section: `WH_NO_FETCH=1` (skip fetch; use last-known remote ref), `WH_ISOLATION_SKIP=1`, `NO_COLOR`, `FORCE_COLOR`, `WH_NO_COLOR=1` (same as --no-color), `WH_DRY_RUN=1` (same as --dry-run). Replace the :48 backticks with `For command options, run:` followed by an indented `worktree-harness <command> --help` (R105). **R2 corrections:** (a) Drop the :48 line entirely; R096 forbids a hint to run help in root help. (b) No `ENVIRONMENT` section, since R087's section list has none. `NO_COLOR`/`FORCE_COLOR`/`WH_NO_COLOR` go in the `--no-color` row ("also NO_COLOR, FORCE_COLOR; --no-color > NO_COLOR > FORCE_COLOR") and `WH_DRY_RUN` in the `--dry-run` row. `WH_NO_FETCH`/`WH_ISOLATION_SKIP` go in the Notes of new/launch/merge (B4-2, B5-1). (c) Headings `Usage:`, `Commands:`, `Global Options:`, `Learn more:` (R087/R231/R060; was `USAGE`/`COMMANDS`/`GLOBAL FLAGS`). (d) Commands are grouped by task (R096), e.g. "Work in a worktree" (new, launch, merge), "Inspect and clean up" (status, gc), "Set up" (init, doctor), and `help` is marked `(default)` because bare `worktree-harness` runs it (bin:81) (R088). (e) Placeholders `<COMMAND>`, `<DIR>`, `<BRANCH>`, `[-- <COMMAND> [<ARG>]...]` (R093/R102). (f) `Learn more: https://github.com/renchris/worktree-harness#readme` replaces `Docs: README.md · docs/DESIGN.md` (:49), which is not a URL (R092). (g) Global Options list `--cwd <DIR>`, `--dry-run`, `-h, --help`, `--no-color`, `-v, --version`, alphabetically (R089/R090). |
| 3 | R055 R084 R304 | bin:68 | Replace `${1:?-C needs a directory}` with `[ $# -ge 2 ] \|\| wh_usage_die "" "-C needs a directory."`, and also accept `-C=<dir>`. `cannot cd to` stays on `wh_die`. **R2 (R466, F38):** the same arm also accepts the canonical `--cwd <DIR>`/`--cwd=<DIR>`, with the message `Option --cwd needs a value.`; see B1-7. |
| 4 | R055 | bin:74 | `wh_usage_die "" "unknown global flag: $1"`. Keep the substring; the pointer now comes from the helper. **R2 (R060, Reference J):** the message is `Unknown option $1 for worktree-harness.` (reason `unknown_option`). Update `test/dispatcher.bats:28` to `*"Unknown option --bogus-flag for worktree-harness."*`. |
| 5 | R304 R260 | bin:137 | Print `wh_err "unknown command: $cmd"` plus `wh_info "See: worktree-harness --help"`, and **drop the full usage dump**. Keep `exit 64` (C1 changes it). Optionally add one close-match suggestion from the command list. **R2 (R084/R105, Reference J):** the headline is `Unknown command $cmd for worktree-harness.`, optionally followed by ` Did you mean <x>?`, then a blank line, `See all options:` and `    worktree-harness --help`. Update `test/dispatcher.bats:22` to `*"Unknown command definitely-not-a-command"*`; `:21` keeps `-eq 64` until C1. |
| 6 | R049 R050 R034 R387 | bin:83, 91, 101, 107 | Split the aliases into their own arms. `create`, `run`, `land` and `prune` call `wh_warn "'<alias>' is deprecated; use 'worktree-harness <canonical>'."` and then run the canonical path unchanged. `prune` adds `"This only previews; pass 'gc --prune' to remove."`. `ls`/`list` stay silent permanent aliases (R049 set). Help and completions keep omitting them. **R2 (R308):** the warnings go through `wh_deprecated` (A.3-3), so each prints at most once per run. |
| 7 | R466 R062 R086 R385 (F38, critic `missedFindings[7]`) | bin:68, 72, 136 | Add `--cwd <DIR>` (row 3) and `-v` (`-v\|--version`) as the canonical spellings. Under D-R2-1, `-C` and `-V` stay accepted: either as deprecated aliases (`wh_deprecated cwd "-C" "--cwd"`, `wh_deprecated version "-V" "--version"`, removal in the next major-equivalent) or, if the operator keeps `-C` as a reserved letter mirroring `git -C`, `-C` stays silent and the reason is recorded in docs/DESIGN.md. Help and completions show only `--cwd` and `-v, --version`. Callers: `test/gc.bats` (6× `-C`) keeps passing; `ci.yml:61` and the Homebrew tap use `--version`. **R2b correction:** the formula's test also runs `-C` (`Formula/worktree-harness.rb:40`). A deprecation warning on stderr doesn't fail it, but removing `-C` later needs the formula changed first. |
| 8 | R100 | bin:65-79 | The global loop honours `__WH_PARSE_ONLY=1` (A.3-6): with no command after the globals it exits 0 instead of printing help; with a command, the command's `wh_parse_opts` exits after its own parse. |
| 9 | R083 R012 | bin:81, 135 | `help <COMMAND> --json` and `help --all --json` are reserved for U-B9. B1 routes `help` arguments other than a command name to `_wh_help_ext` when defined (`declare -F`), and otherwise to the unknown-command path. |
| 10 | R068 (R2b) | bin:65-79 | The global loop accepts `--dry-run=true\|false`, `--no-dry-run`, `--no-color=true\|false` and `--color`, matching A.3-9. Help shows only `--dry-run` and `--no-color`. |

Tests appended to `test/dispatcher.bats` (add `bats_require_minimum_version 1.5.0`):

| Test name | Assertion |
|---|---|
| `help prints to stdout` | `run --separate-stderr "$WH" --help`: status 0, `$output` contains `USAGE`, `[ -z "$stderr" ]` |
| `help <cmd> routes to that command's help` | `run --separate-stderr "$WH" help new`: `$output` contains `worktree-harness new <branch>` |
| `root help works without lib/` | copy `bin/worktree-harness` alone into `$BATS_TEST_TMPDIR/b/`; `run .../b/worktree-harness --help` gives status 0 |
| `root help fits 80 columns` | `run bash -c '"$WH" --help \| LC_ALL=C awk "length>80"'` gives empty `$output`. Bytes are at least characters, so this is stricter than needed. |
| `-C without a directory is a usage error` | `run "$WH" -C`: `-ne 0`, `*"-C needs a directory"*`, `*"See: worktree-harness --help"*` |
| `unknown command prints one line, not the full usage` | `run "$WH" nope`: output lacks `COMMANDS`; status still 64 |
| `deprecated aliases warn; ls does not` | `make_repo; run "$WH" create x --dry-run` gives status 0 and `*"deprecated"*`; `run "$WH" ls` lacks `deprecated` |
| R2: `a deprecated alias warns exactly once` (R308) | `run "$WH" create x --dry-run`: `printf '%s\n' "$output" \| grep -c deprecated` equals 1 |
| R2: `-v prints the same as --version` (R392) | `[ "$("$WH" -v)" = "$("$WH" --version)" ]`; `run "$WH" -v` gives status 0 |
| R2: `--cwd works before and after the command` (R066/R466) | `make_repo; cd /; run "$WH" --cwd "$APP" status` and `run "$WH" status --cwd "$APP"` both give status 0 |
| R2: `root help follows the help layout` (R087/R092/R096) | `run --separate-stderr "$WH" --help`: `$output` contains `Usage:`, `Global Options:`, `Learn more: https://github.com/renchris/worktree-harness`, `--cwd <DIR>`; lacks `GLOBAL FLAGS`, `command-specific`, `-C `, `-V` |
| R2: `unknown option uses the guide's wording` (R060) | replaces `dispatcher.bats:28`: `*"Unknown option --bogus-flag for worktree-harness."*` and `*"See all options:"*` |
| R2 edit of `-C without a directory is a usage error` and `help <cmd> routes …` | assert `*"See all options:"*` instead of `See: worktree-harness --help`, and `worktree-harness new <BRANCH>` instead of `<branch>`. `unknown command prints one line…` asserts the output lacks `Commands:` (was `COMMANDS`) |
| R2 (if D-R2-1 deprecates): `-C warns once and still works` | `run "$WH" -C "$APP" -C "$APP" status`: status 0, one `deprecated` line |
| R2b: `global booleans parse =true and =false` (R068) | `make_repo; run "$WH" --dry-run=false status` gives status 0; `run "$WH" --dry-run=maybe status` gives `-ne 0` and `*"takes true or false"*` |

Size: ~70 source + ~80 tests = **~150 LOC** (estimated). **R2:** +~45 source, +~45 tests = **~240 LOC** (estimated, same method). **R2b:** +~10 = **~250 LOC** (estimated).

### B2: `lib/cmd_gc.sh` + `test/gc.bats`

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R325 R023 R015 R064 (F1, F15) | cmd_gc.sh:30-37 | Replace the `case "${1:-}"` with `wh_parse_opts gc 0 "--prune=prune --force=force_alias" -- "$@"`. If `force_alias=1`, call `wh_warn "gc --force is deprecated; use --prune."` and set `prune=1` (R009/R050; behaviour unchanged). Then **dry-run wins**: `[ "$WH_DRY_RUN" = 1 ] && [ "$prune" = 1 ] && { wh_info "--dry-run overrides --prune: nothing will be removed."; prune=0; }`. This makes `--dry-run gc --prune`, `gc --prune --dry-run` and `gc --dry-run --prune` all preview only. |
| 2 | R083 R023 R089 | cmd_gc.sh:11-20 | `_wh_gc_usage` prints to stdout. Usage line `worktree-harness gc [--prune] [--dry-run]`. Add an Options block (`--dry-run`, `--prune`; `--force` is not listed because it is deprecated). |
| 3 | R275 (F5) | after cmd_gc.sh:38 | `wh_require_repo gc`. Today :41 exits 128 with no output (measured by the verifier's errexit simulation). |
| 4 | R017 R194 (F8, compatible part) | cmd_gc.sh:56, 67 | **Dirty gate:** `if ! st="$(git -C "$wt" status --porcelain 2>&1)"; then wh_info "KEEP   $base [${br:-detached}] — couldn't check dirty state: ${st%%$'\n'*}"; continue; fi; [ -n "$st" ] && { …existing dirty KEEP…; continue; }`. **Idle gate:** send find's stderr to a `mktemp` file and keep `\| head -1 \|\| true`, because head may SIGPIPE find under pipefail. If the error file is non-empty, KEEP with `couldn't check recency: <first line>`. A gate that can't be evaluated keeps the worktree. |
| 5 | R318 R003 R339 R275 R017 (F7) | cmd_gc.sh:78-94 | Add counters `removed`, `failed`, `kept` and `cands`. Replace :79 with `if err="$(git worktree remove "$wt" 2>&1)"`. On failure print `wh_err "failed  $base [$br]: ${err%%$'\n'*}"` and `wh_info "  inspect: git -C $(printf %q "$wt") status --ignored"`. Add `git worktree unlock` when the message says locked. Mention `--force` only with "deletes ignored files such as .env". After the loop, in prune mode, print `Removed X of Y worktrees. F failed.` (Reference J Partial) and `Removals are per worktree, not atomic; re-running gc --prune is safe.` End with `[ "$failed" -eq 0 ]` (exit 1 on partial). |
| 6 | R173 R021 (F12) | cmd_gc.sh:80 | In the success branch, `printf '%s\n' "$wt"` on **stdout** (the removed path). Dry-run prints nothing on stdout. **R2: superseded by row 10** (stdout only on exit 0, R176). |
| 7 | R217 (F17) | cmd_gc.sh:75 | `$(wh_plural "$n" commit commits) not in $def (merge first)`. Keep `not in $def` (gc.bats:21). Leave the "?" count as is. |
| 8 | R212 R191 R179 R002 (F37, critic `missedFindings[6]`) | cmd_gc.sh:52-53, 57, 60, 63, 68, 71, 75, 80, 82, 85, and the new lines in rows 4–5 | Every gc row prints the full worktree path `$wt`, never shortened (R212). The preview names its exact target (R179/R002). `$base` stays only for the `HARNESS_GC_KEEP` match at :52-53, because that setting is documented "by basename" (cmd_init.sh:58, config.sh:33). Rows 4–5 read `$wt` wherever they wrote `$base`. Callers: no test asserts a basename row (measured: gc.bats asserts only `dirty`, `not in main`, `modified <`). `docs/demo.cast:37` is hand-edited in B7. |
| 9 | R183 R184 R231 R033 (F39, critic `missedFindings[8]`) | cmd_gc.sh:44, 53, 57-71, 80, 82, 85, 93 | One label set: Title Case, an 8-column label field, no trailing colons. `Keep` replaces both `skip` (:53) and `KEEP` (:57-71). `Remove` replaces `WOULD remove` (:85) and is the same verb as the receipt (R033). `Removed` (:80) and `Failed` (:82). The :44 dry-run banner stays as the context line. The :93 heading becomes `Remaining worktrees`, plain text with no colon (R184). Example row: `Keep    /…/wt/app/feat [feat] — dirty (uncommitted work)`. Callers: as row 8; `docs/demo.cast:38` is edited in B7. |
| 10 | R176 R318 R173 (critic `unmentionedRules[21]`) | cmd_gc.sh:78-94 (amends rows 5–6) | Collect removed paths in a newline-joined variable. Print them on stdout **only when `failed` is 0**, after the loop. On a partial failure stdout stays empty, the Partial report on stderr lists each removed path as a `Removed` row, and the exit is 1. **R2b (R173):** print them through `wh_print_id` (A.3-11). |
| 11 | R326 (critic `unmentionedRules[32]`) | after the loop | When no worktree passes every gate (`cands` = 0), print `No worktrees are ready to remove.` on stderr, exit 0, in both modes, before `Remaining worktrees`. |
| 12 | R091 R100 R101 | `_wh_gc_usage` (:11-20) | Add `Examples:`: `    worktree-harness gc` (preview) and `    worktree-harness gc --prune` (remove). C2 adds the automation example `    worktree-harness gc --prune --yes`. |

Tests appended to `test/gc.bats` (add `bats_require_minimum_version 1.5.0`). Copy the setup of `gc reaps a merged + idle worktree…` (gc.bats:34-39) as `reapable_fixture`:

| Test name | Assertion |
|---|---|
| `global --dry-run beats gc --prune` | `run "$WH" -C "$APP" --dry-run gc --prune`: `[ -d "$WT_HOME/app/feat" ]` and `*"WOULD remove"*` (R2: assert `*"Remove  $WT_HOME/app/feat"*`, rows 8–9) |
| `gc --prune --dry-run removes nothing` | same assertions |
| `gc --prune rejects extra arguments` | `run "$WH" -C "$APP" gc --prune junk`: `-ne 0` and `*"Unexpected argument junk"*` |
| `gc --force warns and still prunes` | `*"deprecated"*` and `[ ! -d "$WT_HOME/app/feat" ]` |
| `gc --prune prints removed paths on stdout` | `run --separate-stderr`: `[ "$output" = "$WT_HOME/app/feat" ]` |
| `gc --prune exits 1 when a removal fails` | `git -C "$APP" worktree lock "$WT_HOME/app/feat"`, then `status -eq 1`, `*"locked"*`, `*"1 failed"*`, dir still exists |
| `gc keeps a worktree whose dirty check fails` | `printf 'gitdir: /nonexistent\n' > "$WT_HOME/app/feat/.git"`: dir kept, `*"couldn't check"*` (today this would be kept as "detached HEAD", so the reason text proves the fix) |
| `gc outside a repo fails with a message` | `make_norepo; run "$WH" gc`: `status -eq 1`, `*"outside a git repository"*` |
| R2: `gc rows print full worktree paths and one label set` (R212/R183) | `reapable_fixture; run "$WH" -C "$APP" gc`: `*"Remove  $WT_HOME/app/feat"*`; `printf '%s\n' "$output" \| grep -cE '^(KEEP\|WOULD\|skip) '` equals 0; output contains the line `Remaining worktrees` |
| R2: `gc --prune prints nothing on stdout when any removal fails` (R176) | two reapable worktrees `feat` and `feat2`; `git -C "$APP" worktree lock "$WT_HOME/app/feat2"`; `run --separate-stderr "$WH" -C "$APP" gc --prune`: status 1, `[ -z "$output" ]`, `$stderr` has `Removed $WT_HOME/app/feat` and `1 failed` |
| R2: `gc with nothing to remove says so` (R326) | `make_repo; run "$WH" -C "$APP" gc`: status 0, `*"No worktrees are ready to remove."*` |
| R2: `every gc --help example parses` (R100) | `assert_help_examples_parse gc` |

Size: ~70 source + ~90 tests = **~160 LOC** (estimated). **R2:** +~30 source, +~45 tests = **~235 LOC** (estimated). **R2b:** +~5 = **~240 LOC** (estimated).

### B3: `lib/cmd_status.sh` + `test/status.bats` (new)

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R063 R064 R243 R438 | cmd_status.sh:19-26 | `wh_parse_opts status 0 "--human=human --json=json --porcelain=porcelain" -- "$@"`. Combining `--json` and `--porcelain` calls `wh_usage_die status "Can't use --json with --porcelain."`. **Conflict resolved:** F16 wanted `--human` deprecated, but F11/C4 give it a real meaning ("force the aligned table even when piped"). Keep it and document it; do **not** warn. **R2b correction (R438, R009):** documenting it teaches a second format selector, which R438 bans. `--human` stays accepted with its aligned-table meaning (caller compatibility; C4's test) and is never advertised: not in help, completions, README or B9's metadata. `--porcelain` is a documented script interface, so it stays taught (`lib/cmd_status.sh:6-7, :15`, README.md:240, SKILL.md:38). D-R2-16 records the alternatives. |
| 2 | R083 R095 R023 | cmd_status.sh:9-17 | Usage goes to stdout. Wrap :15 (92 chars, measured by the verifier). Document `--human`, `--json` and the 5 porcelain columns. **R2b:** drop `--human` from this list (row 1). |
| 3 | R275 (F5) | after :27 | `wh_require_repo status` (today :30 exits 128 silently). |
| 4 | R115 R199 R209 (F10) | :34-35, :70 | Use `$WH_O_DIM`/`$WH_O_RESET` (stdout-resolved) instead of `$WH_C_DIM`, so `status \| cat` on a terminal emits no ESC. Porcelain and JSON stay unstyled. |
| 5 | R017 R194 (F8, human part) | :42, :48-49 | `a="$(…)" \|\| a='?'` and the same for `b`. In human mode, print `+?/-?` and one stderr warning: `can't compare <br> with <def>: no local '<def>' branch`. **Porcelain shim:** while porcelain, map `?` back to `0` (comment `# C3 removes this shim`) so `--porcelain` stays byte-identical in Wave B. Treat a dirty check that fails at :42 the same way (`?` in human mode, `""` in porcelain until C3). |
| 6 | R243 R248 R244 R209 (F11, additive) | new `--json` branch | One document on stdout: `{"worktrees":[{"kind":"main\|linked","branch":"…","dirty":true\|false\|null,"ahead":N\|null,"behind":N\|null,"ports":{"PORT":3001},"path":"…"}],"pagination":{"next":null}}`, built with `wh_json_str`. Ports are an object keyed by env name, because the names are lost in today's comma list. In JSON mode stderr stays empty: no footer and no `?` warning. |
| 7 | R217 (F11) | :70 | Footer count: `$(wh_plural "$count" worktree worktrees)`. Moving the footer to stderr is C4. |
| 8 | R252 R454 R436 (critic `unmentionedRules[28]`) | parser spec (row 1) and the `--json` branch | Add `--fields=fields:` (`--fields <FIELDS>`), a comma-separated list drawn from `kind,branch,dirty,ahead,behind,ports,path`. Each worktree object keeps only those keys, and `pagination` is unchanged. An unknown field calls `wh_usage_die status "Unknown field <x> for worktree-harness status --fields. Valid fields: kind, branch, dirty, ahead, behind, ports, path."`. `--fields` without `--json` calls `wh_usage_die status "Can't use --fields without --json."`. Only `,` and `[a-z]` are accepted, so the values never reach a shell or awk program. |
| 9 | R251 R410 R250 | `--json` branch | Emit the document through `wh_json_out` (A.3-7): 2-space indentation on a TTY, compact when piped. Empty ports are `{}` and `ahead`/`behind` for the main checkout are `null`; neither is ever omitted (R250). |
| 10 | R253 R255 R261 R262 R244 | `--json` mode | `WH_JSON=1` is set by the parser prescan (A.3-7) before `wh_require_repo`/`wh_load_config`. Every failure is therefore one JSON line on stderr with nothing on stdout: outside a repo gives `repository_not_found` (exit 1), `.harnessrc` errors give `invalid_config` (B6-8, exit 1), and usage errors give `unknown_option`/`invalid_arguments`. A signal gives `canceled`. The human `?` warning (row 5) is suppressed, and its condition shows only as the `null` value. |
| 11 | R091 R100 R101 | `_wh_status_usage` (:9-17) | `Examples:` `    worktree-harness status`, `    worktree-harness status --json --fields branch,path`, `    worktree-harness status --porcelain`. |
| 12 | R106 R243 | PR body | List the `--json` result schema (field, type, nullability) for U-B9 to encode in `lib/help_meta.sh`. |

Tests in `test/status.bats` (new; `bats_require_minimum_version 1.5.0`):

| Test name | Assertion |
|---|---|
| `--porcelain output is unchanged (golden)` | after `make_repo; "$WH" new feat`: second porcelain line is exactly `linked<TAB>feat<TAB>+0/-0<TAB>3001<TAB>$WT_HOME/app/feat` (locks the contract before C3/C4) |
| `--json is one valid document with ports by name` | `run --separate-stderr "$WH" status --json`: `[ -z "$stderr" ]`; `command -v python3 \|\| skip`; then `python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["worktrees"][1]["ports"]=={"PORT":3001}'` |
| `--json with --porcelain is a usage error` | `-ne 0`, `*"Can't use --json with --porcelain"*` |
| `footer uses a correct plural` | fresh repo: `*"(1 worktree "*` |
| `piped stdout carries no ANSI even when stderr is a terminal` | wrap in `script` to give stderr a pty: macOS `script -q /dev/null bash -c '"$WH" status \| od -c'`, Linux `script -qec "…" /dev/null`; assert no `033`. Skip with a reason if `script` is unavailable. The unit test in common.bats is the primary proof. |
| `status outside a repo fails with a message` | `make_norepo`, `status -eq 1`, `*"outside a git repository"*` |
| R2: `--fields keeps only the named keys` (R252) | `run --separate-stderr "$WH" status --json --fields branch,path`; `command -v python3 \|\| skip`; `python3 -c 'import json,sys;d=json.load(sys.stdin);assert all(set(w)=={"branch","path"} for w in d["worktrees"])'` |
| R2: `--fields rejects an unknown field and lists the valid ones` | `run "$WH" status --json --fields nope`: `-ne 0`, `*"Valid fields: kind, branch, dirty"*` |
| R2: `--fields without --json is a usage error` | `-ne 0`, `*"Can't use --fields without --json."*` |
| R2: `--json failure is one JSON line on stderr` (R253/R261) | `make_norepo; run --separate-stderr "$WH" status --json`: status 1, `[ -z "$output" ]`, `[ "$(printf '%s\n' "$stderr" \| wc -l)" -eq 1 ]`, `*'"reason":"repository_not_found"'*` |
| R2: `piped --json is compact` (R251) | `[ "$(printf '%s\n' "$output" \| wc -l)" -eq 1 ]` |
| R2: `every status --help example parses` (R100) | `assert_help_examples_parse status` |

Size: ~75 source + ~70 tests = **~145 LOC** (estimated). **R2:** +~40 source, +~50 tests = **~235 LOC** (estimated).

### B4: `lib/cmd_new.sh`, `lib/cmd_launch.sh`, `test/new.bats`, `test/launch.bats` (new)

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R063 R064 R066 (F15) | cmd_new.sh:146-158; cmd_launch.sh:34-46 | `new`: `wh_parse_opts new 1 "" -- "$@"; branch="${WH_ARGS[0]:-}"`. A missing branch calls `wh_usage_die new "Missing branch name."` and **no longer dumps full usage** (F3). `launch`: `wh_parse_opts launch rest "" -- "$@"`, then `agent_cmd=(${WH_ARGS[@]+"${WH_ARGS[@]}"})`. |
| 2 | R083 R079 | cmd_new.sh:6-17; cmd_launch.sh:12-22 | Usage goes to stdout. Add `WH_NO_FETCH=1` to both helps and keep `WH_ISOLATION_SKIP` in launch. |
| 3 | R275 (F5) | after cmd_new.sh:159 | `wh_require_repo new`. Not in launch, which is documented to work outside a repo (README.md:181). |
| 4 | R003 R275 R318 R335 R007 R339 R416 (F13, root cause) | cmd_new.sh:22-49, 160; cmd_launch.sh:74-76 | **Stop calling `wh_create_worktree` inside `$(...)`.** In bash, errexit is off inside a command substitution and the root signal trap does not reach it. The function now sets the global `WH_WT_PATH` and returns a status. Callers run it as a statement: `wh_cmd_new` prints `$WH_WT_PATH` on stdout (same bytes as today, new.bats:13-17), and launch reads `$WH_WT_PATH`. Right after `git worktree add` succeeds, set `WH_PARTIAL_PATH`/`WH_PARTIAL_BRANCH`; clear both after setup succeeds. Chain `wh_copy_files "$path" && wh_run_install "$path" && wh_assign_ports "$path" && wh_run_setup "$path" \|\| _wh_provision_failed "$path" "$branch"`. `_wh_provision_failed` prints **one** error: `Failed to provision worktree <path> (branch <b>). The worktree and branch were left in place.`, then `To remove them:` with `git worktree remove --force <%q path>` and `git branch -D <%q b>` (one per line), then `${WH_FAIL_HINT:-}`, then exit 1. Launch sets `WH_FAIL_HINT="Refusing to launch un-isolated (WH_ISOLATION_SKIP=1 to override)."` and drops its duplicate outer `\|\| wh_die` (R310). |
| 5 | R003 (F13) | cmd_new.sh:58-68, 81, 129-130 | `wh_copy_files`: `cp -R … \|\| { wh_err "copy failed: $f"; failed=$((failed+1)); continue; }`. Count only successful copies, report `copied $(wh_plural $n file files)`, and `return 1` if `failed > 0`. `wh_run_install` and `wh_run_setup` print their one-line error and `return 1` instead of `wh_die`. |
| 6 | R325 R187 R003 (F2) | cmd_new.sh:35-38, 161-163; cmd_launch.sh:76-78 | Move the dry-run return **before** `mkdir -p` (:36): `wh_step "would: git worktree add $path -b $branch $base"`, set `WH_WT_PATH`, `return 0`. `wh_cmd_new` in dry-run prints the path on stdout (README.md:100 / SKILL.md:59 capture contract) and logs `dry-run: would create worktree $path (branch: $branch). Nothing changed.` instead of `worktree ready`, with no next steps. Launch in dry-run skips the `[ -d "$path" ]` check and the "isolated session" line, logs `dry-run: would isolate in $path (branch: $branch)`, then calls `wh_exec_agent` (prints "would exec"). (B6 makes `wh_base_ref` skip the fetch in dry-run.) |
| 7 | R351 R353 (F18) | cmd_new.sh:59-62, 112-116 | Copy secret-pattern files inside `( umask 077; cp -R … )`. Keep `chmod 0600` only when `[ -f "$path/$f" ]`, because chmod on a copied directory would remove its x bit. Build `.harness.env` content in a variable and `wh_atomic_write "$envf"` it (`\|\| return 1`). Drop the info/exclude locking and the HARNESS_COPY path validation (see Dropped). |
| 8 | R044 (F19) | cmd_new.sh:84-88, 110 | Write `# harness-offset=N` as the first line of `.harness.env`. `status`'s awk at cmd_status.sh:55 reads only `^export`, so its output does not change. Rewrite `wh_worktree_offset <new-path>` to walk `git worktree list --porcelain`, skipping main and `<new-path>`. Read each worktree's `# harness-offset=`; for older files without it, use the first `export NAME=V` minus NAME's base from `HARNESS_PORTS`. Collect used offsets into a space-padded string (`case " $used " in *" $k "*`; no assoc arrays) and return the smallest k ≥ 1 not in it. Fresh repos keep 1, 2, … (new.bats:10, :51; README "offset by 1"). |
| 9 | R103 R105 R277 R217 (F17) | cmd_new.sh:41, 68, 139-142 | :41 becomes `wh_die "Couldn't create worktree $path for branch '$branch' (git's message is above)."`. Next steps: each benefit on its own short line, then the command on its own indented line, with `cd $(printf %q "$path")` and no trailing `# …` comments. Keep `worktree-harness gc --prune` as the human hint (it prompts on a TTY after C2). |
| 10 | (dropped-finding residual, optional) | cmd_launch.sh:52 | `set -f; agent_cmd=($HARNESS_AGENT); set +f`, so glob characters in `HARNESS_AGENT` don't expand against the cwd. 2 LOC. |
| 11 | R473 R092 (critic `unmentionedRules[43]`) | cmd_new.sh:6-17; cmd_launch.sh:12-22 | `new` and `launch` overlap, since both create worktrees, and neither help names the other (measured by reading both usage heredocs). `new` Notes: `To create a worktree and start your agent in it in one step, use worktree-harness launch.` `launch` Notes: `To create a named worktree without starting an agent, use worktree-harness new <BRANCH>.` |
| 12 | R238 R236 (critic `unmentionedRules[27]`) | cmd_new.sh:135-144 (the row 9 rewrite) | The optional `Next steps:` block prints only when `wh_guidance_enabled` (A.3-8). The `Failed to provision` recovery (row 4) and the stdout path always print. |
| 13 | R091 R100 R101 R093 R102 | both usage functions | `new` Examples: `    worktree-harness new <BRANCH>` and `    worktree-harness new <BRANCH> --dry-run`. `launch` Examples: `    worktree-harness launch` and `    worktree-harness launch -- <COMMAND>`. Usage lines: `worktree-harness new <BRANCH> [options]`, `worktree-harness launch [options] [-- <COMMAND> [<ARG>]...]`. |

Tests (`test/new.bats` append; `test/launch.bats` new; both with `bats_require_minimum_version 1.5.0`):

| Test name | Assertion |
|---|---|
| `new --dry-run creates no parent dir and prints the planned path` | `run --separate-stderr "$WH" new feat --dry-run`: status 0, `[ "$output" = "$WT_HOME/app/feat" ]`, `[ ! -d "$WT_HOME/app" ]`, `*"would create"*` in `$stderr` |
| `globals work after the command` | `run "$WH" new feat --no-color --dry-run` gives status 0 |
| `new without a branch points at help` | `-ne 0`, `*"See: worktree-harness new --help"*`, output lacks `Create a git worktree` (no usage dump) (R2: assert `*"See all options:"*` and `*"worktree-harness new --help"*`) |
| `a failed copy fails new and names the cleanup` | `[ "$(id -u)" = 0 ] && skip`. Add `mkdir -p "$APP/sec/x"`, `chmod 000 "$APP/sec/x"`, and `HARNESS_COPY+=("sec")` to `.harnessrc`. Then `run --separate-stderr "$WH" new feat`: `status -eq 1`, `[ -z "$output" ]`, `$stderr` contains `Failed to provision worktree` and `git branch -D feat`. `chmod 755` in teardown. |
| `a failing setup prints exactly one error` | `HARNESS_SETUP=( "false" )`: `status -eq 1`; `printf '%s\n' "$stderr" \| grep -c '^Error:'` equals 1 |
| `port offsets are reused after a worktree is removed` | `new feat; new feat2; git -C "$APP" worktree remove "$WT_HOME/app/feat"; new feat3`: `grep -q PORT=3001 "$WT_HOME/app/feat3/.harness.env"` |
| `copied secret files are owner-only` | `ls -l "$WT_HOME/app/feat/.env.local"` starts with `-rw-------` |
| `TERM during setup names the partial worktree` | `HARNESS_SETUP=("sleep 3")`; start `"$WH" new feat 2>"$err" &`; poll up to 5 s for `.harness.env`; `kill -TERM $!`; `wait $!` gives 143; `grep -q "$WT_HOME/app/feat" "$err"`. Use TERM, not INT, because background jobs in non-interactive bash ignore SIGINT. Mark it `skip` if flaky in CI. |
| launch.bats: `launch --dry-run on the main checkout exits 0 and creates nothing` | `run "$WH" launch --dry-run -- true`: status 0, `*"would exec: true"*`, `[ -z "$(ls "$WT_HOME/app" 2>/dev/null)" ]`, `[ -z "$(git -C "$APP" branch --list 'wt-*')" ]` |
| launch.bats: `launch still runs outside a repo` | `make_norepo; run "$WH" launch -- true` gives status 0 |
| launch.bats: `a failed isolation prints one error` | `HARNESS_SETUP=("false")`: `status -eq 1`, exactly one `^Error:` line, `*"Refusing to launch un-isolated"*` |
| R2 launch.bats: `launch passes the child's exit code through` (R400, Reference L) | `make_repo; "$WH" new feat; cd "$WT_HOME/app/feat"` (linked worktree, so launch execs in place); `run "$WH" launch -- sh -c 'exit 42'`: status 42 |
| R2 launch.bats: `launch passes argv with spaces and metacharacters unchanged` (R400) | same fixture; `run --separate-stderr "$WH" launch -- printf '%s\|' 'a b' '$HOME' '*'`: `[ "$output" = 'a b\|$HOME\|*\|' ]` |
| R2 new.bats: `a mistyped option creates nothing` (R394/R064) | `run "$WH" new feat --dyr-run`: `-ne 0`, `*"Unknown option --dyr-run for worktree-harness new."*`, `[ ! -d "$WT_HOME/app/feat" ]`, `[ -z "$(git -C "$APP" branch --list feat)" ]` |
| R2 new.bats: `the guidance variable hides next steps but keeps the path` (R238) | `WH_GUIDANCE_DISABLED=1 run --separate-stderr "$WH" new feat`: status 0, `[ "$output" = "$WT_HOME/app/feat" ]`, `$stderr` lacks `Next steps` |
| R2: `new and launch help name each other` (R473) | `run "$WH" new --help` contains `worktree-harness launch`; `run "$WH" launch --help` contains `worktree-harness new <BRANCH>` |
| R2: `every new/launch --help example parses` (R100) | `assert_help_examples_parse new`; `assert_help_examples_parse launch` |

Size: ~150 source + ~125 tests = **~275 LOC** (estimated). **R2:** +~15 source, +~60 tests = **~350 LOC** (estimated).

### B5: `lib/cmd_merge.sh`, `lib/cmd_init.sh`, `test/merge.bats`, `test/init.bats` (new)

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R063 R064 R083 R079 | cmd_merge.sh:12-35 | `wh_parse_opts merge 0 "--no-verify=skip_verify" -- "$@"`. Usage goes to stdout and gains a `WH_NO_FETCH=1` line. |
| 2 | R275 R003 (F5) | before cmd_merge.sh:39; :97; :100 | `wh_require_repo merge`. :97 becomes `git -C "$def_wt" merge --ff-only "$branch" >&2 \|\| wh_die "Couldn't fast-forward $def at $def_wt to $branch (git's message is above). $branch is rebased and gated; $def is unchanged. Fix $def_wt, then run: git -C $(printf %q "$def_wt") merge --ff-only $branch"`. :100 becomes `git fetch . "$branch:$def" \|\| wh_die "Couldn't move $def to $branch (git's message is above). $branch is rebased; $def is unchanged. Retry: git fetch . $branch:$def"`. |
| 3 | R016 R173 R021 (F12) | :74, :91, :97, :102, :54 | Redirect `git rebase "$base" >&2`, `eval "$HARNESS_MERGE_GATE" >&2` (still visible, exit status unchanged) and the ff merge to stderr. After the :102 receipt, `git rev-parse "$def"` on **stdout** (full SHA). In the "already contains" branch (:54), also print `git rev-parse "$def"` on stdout. Dry-run prints nothing on stdout. **R2b (R173):** print through `wh_print_id` (A.3-11). |
| 4 | R359 (F20) | :60 | `git --no-pager log --no-decorate --format='%h %s' --reverse "$base..$branch" 2>/dev/null \| wh_sanitize_stream \| sed 's/^/   + /' >&2 \|\| true` |
| 5 | R004 R280 (F17) | :92 | `wh_err "merge gate failed on the rebased tree: $HARNESS_MERGE_GATE. $def was not updated."`, then `wh_info "Fix the failure, commit, then re-run:"` and `wh_info "  worktree-harness merge"`, then `exit 1`. The :78 `exit 2` stays until C1. |
| 6 | R083 R087 R064 | cmd_init.sh:5-11 | `wh_parse_opts init 0 "" -- "$@"`. A new `_wh_init_usage` heredoc (stdout) with Usage, a one-line summary, Options (`--dry-run`) and an Example; it replaces the `wh_info` one-liner at :7. |
| 7 | R351 R350 (F18) | cmd_init.sh:15, 22-61 | Write the heredoc through `wh_write_new "$rc"`. If it returns 1, use the same `.harnessrc already exists at $rc — edit it directly.` message (exit 1). |
| 8 | R173 (F12) | cmd_init.sh:62 | `printf '%s\n' "$rc"` on stdout before the `wh_ok`. Not printed in dry-run. **R2b (R173):** print through `wh_print_id` (A.3-11). |
| 9 | R103 R104 R105 (critic `unmentionedRules[10]`) | row 2's two recovery commands | Quote the branch as well as the path: `git -C %q merge --ff-only %q` and `git fetch . %q` (with `printf %q "$branch:$def"`), each on its own indented line after a benefit sentence. `git check-ref-format` accepts `$`, `(`, `;`, `&` and backtick in branch names, so an unquoted suggestion can break, or run code, when pasted. Only local values appear; no remote value or secret reaches a suggestion (R104). |
| 10 | R091 R100 R101 | `_wh_merge_usage` (:12-23); `_wh_init_usage` (row 6) | merge Examples: `    worktree-harness merge` and `    worktree-harness merge --no-verify`. init Examples (replacing row 6's single Example): `    worktree-harness init` and `    worktree-harness init --dry-run`. These are the help examples critic `missedFindings[11]` found untested; row 6's example is now covered by the parser test below. |

Tests (`test/merge.bats` append; `test/init.bats` new; `bats_require_minimum_version 1.5.0`):

| Test name | Assertion |
|---|---|
| `merge prints the landed commit on stdout` | `run --separate-stderr bash -c "cd '$WT_HOME/app/feat' && '$WH' merge"`: `[ "$output" = "$(git -C "$APP" rev-parse main)" ]` |
| `merge on an already-landed branch prints the same SHA` | re-run: same assertion, status 0 |
| `merge --dry-run prints nothing on stdout` | `[ -z "$output" ]` |
| `merge strips control characters from commit subjects` | commit with subject `$'evil \033[31m red'`: `[[ "$stderr" != *$'\033'* ]]` and `*"evil"*` |
| `merge outside a repo fails with a message` | `make_norepo`: `status -eq 1`, `*"outside a git repository"*` |
| `a blocked fast-forward names the partial state` | `printf x > "$APP/feat.txt"` (untracked file blocks ff in the main checkout): `status -eq 1`, `*"Couldn't fast-forward main"*`, `git -C "$APP" rev-parse main` unchanged |
| init.bats: `init writes .harnessrc and prints its path` | `make_repo; git rm -q .harnessrc; git commit -qm rm`; `run --separate-stderr "$WH" init`: `[ "$output" = "$APP/.harnessrc" ]`, no `.harnessrc.*` temp siblings |
| init.bats: `init never overwrites` | second run: `-ne 0`, `*"already exists"*`, file checksum unchanged |
| init.bats: `init --help prints usage on stdout` / `init rejects extra arguments` | `$output` has `worktree-harness init`; `init junk` gives `-ne 0` |
| R2: `every merge/init --help example parses` (R100) | `assert_help_examples_parse merge`; `assert_help_examples_parse init` (in `test/merge.bats` and `test/init.bats`) |
| R2: `a blocked fast-forward quotes the branch in its recovery command` (R103) | the blocked-ff fixture with branch `'feat$(x)'` (`new 'feat$(x)'`): `*'feat\$\(x\)'*` in output; the unquoted `feat$(x)` never appears after `merge --ff-only ` |

Size: ~60 source + ~100 tests = **~160 LOC** (estimated). **R2:** +~6 source, +~30 tests = **~195 LOC** (estimated). **R2b:** +~5 = **~200 LOC** (estimated).

### B6: `lib/config.sh`, `lib/pm.sh`, `lib/cmd_doctor.sh`, `test/config.bats`, `test/doctor.bats` (new)

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R325 (F2) | config.sh:102-106 | In dry-run, `wh_step "would fetch $HARNESS_REMOTE $def (skipped: dry run)"` and skip the fetch. A fetch updates remote-tracking refs, which is a mutation. |
| 2 | R313 R292 R017 (F14, compatible part) | config.sh:104-105 | Run the fetch with `GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 fetch --quiet …`. For ssh, add `-o ConnectTimeout=10 -o BatchMode=yes` by setting `GIT_SSH_COMMAND`, but **only when** `GIT_SSH_COMMAND` and `GIT_SSH` are unset and `git config core.sshCommand` is empty; otherwise the user's ssh setup would be overridden. Capture stderr. On failure, `wh_warn "Couldn't fetch $def from $HARNESS_REMOTE ($(git remote get-url "$HARNESS_REMOTE")): <first stderr line>. Using last-known $HARNESS_REMOTE/$def."` and **still continue**; failing closed is C5. An optional wall-clock watchdog (`fetch & … sleep 120; kill`) is not planned, because it interacts with the root trap. |
| 3 | R138 R303 R008 (F21) | config.sh:67-75 | Factor out `wh_config_problems`, which prints one line per invalid key (BASE_POLICY, GC_IDLE_MIN) with the **exact current messages** and never exits. `wh_validate_config` becomes `p="$(wh_config_problems)"; [ -z "$p" ] \|\| wh_die "${p%%$'\n'*}"`; config.bats:17 and :25 still match. Add `wh_config_warnings` for an unknown `HARNESS_PACKAGE_MANAGER` (allowed list taken from `pm.sh`) and malformed `HARNESS_PORTS` entries (must match `NAME=digits` with NAME a shell identifier). These are warnings in B6 and become errors in C5. |
| 4 | R074 R013 (F14, compatible part) | pm.sh:43 | Split `none` from `*)`. Unknown names print `wh_warn "HARNESS_PACKAGE_MANAGER '$pm' is not a known package manager; skipping install."` to stderr. Behaviour is otherwise unchanged until C5. Expose `WH_PM_KNOWN="auto pnpm npm yarn bun pip pipenv poetry uv cargo go none"`. |
| 5 | R138 R303 (F21) | cmd_doctor.sh:33-42 | `if _err="$( ( set +e; . "$rc" ) 2>&1 >/dev/null )"`. On failure, print `.harnessrc fails to load:`, then bash's own `file: line N: …` lines indented, then keep the `bash -n` hint. Only stderr is relayed, never variable values. |
| 6 | R008 R014 (F21) | cmd_doctor.sh:47-50 | Replace the hand-written BASE_POLICY check with a loop over `wh_config_problems` (issues++ per line) and `wh_config_warnings` (warn only). Add a `gc idle (min) :` summary row. Keep every existing summary row text (config.bats:8-9, :33, :41). |
| 7 | R083 R064 R217 | cmd_doctor.sh:5-10, 26, 67 | `wh_parse_opts doctor 0 "" -- "$@"`, plus a `_wh_doctor_usage` heredoc on stdout. `$(wh_plural "$issues" issue issues)`. `return "$issues"` stays until C1. |
| 8 | R253 R255 R138 | config.sh:62, 70, 73 (and row 3's `wh_validate_config`) | Config failures go through `wh_fail 1 invalid_config "<same message>"` (A.3-7), so the text and exit 1 are unchanged (config.bats:17, :25 still match) and `status --json` reports them as one JSON line (B3-10). |
| 9 | R091 R100 | `_wh_doctor_usage` (row 7) | `Examples:` `    worktree-harness doctor`. |

Tests (`test/config.bats` append; `test/doctor.bats` new):

| Test name | Assertion |
|---|---|
| `doctor flags a non-numeric HARNESS_GC_IDLE_MIN` | `-ne 0`, `*"HARNESS_GC_IDLE_MIN"*` (today doctor says "no blocking issues") |
| `doctor shows where .harnessrc breaks` | `printf 'if then\n' >> .harnessrc`: `*".harnessrc: line"*` |
| `doctor warns about an unknown package manager` | `HARNESS_PACKAGE_MANAGER="pnmp"`: status 0, `*"pnmp"*` |
| `new warns when the package manager is unknown` | status 0, stderr `*"not a known package manager"*` |
| `a failed fetch names the remote and continues` | `git -C "$APP" remote set-url origin "$BATS_TEST_TMPDIR/missing.git"`; `run "$WH" new feat`: status 0, `*"Couldn't fetch"*`, `*"missing.git"*` |
| `new --dry-run does not fetch` | push a new commit to origin from a second clone; `"$WH" new feat --dry-run`; `git -C "$APP" rev-parse origin/main` unchanged |
| R2: `every doctor --help example parses` (R100) | `assert_help_examples_parse doctor` |
| R2 (lands in U-B9, which runs after B3 and B6): `a config error under status --json is one invalid_config line` (R253) | see B9 tests |

Size: ~85 source + ~85 tests = **~170 LOC** (estimated). **R2:** +~5 source, +~5 tests = **~180 LOC** (estimated; the cross-unit JSON config test moved to B9).

### B7: docs (merges last in Wave B; R2: after U-B8, before U-B9; R2b: after U-B11). Owns `README.md`, `SKILL.md`, `CHANGELOG.md`, `docs/demo.cast`, `share/completions/*` (R2: and `docs/DESIGN.md`; R2b: and `docs/THREAT_MODEL.md`)

- `README.md:15`: `copied 1 gitignored file(s)` becomes `copied 1 file`. `:97`: ports are reused after a worktree is removed. Commands table (:240-245): `status [--porcelain\|--json]`, `gc [--prune] [--dry-run]`, global flags plus the env vars (`WH_NO_FETCH`, `WH_ISOLATION_SKIP`, `NO_COLOR`, `FORCE_COLOR`). The config section gains `WH_NO_FETCH`.
- `SKILL.md:38`: `status [--porcelain|--json]`. `:43`: the `--dry-run` promise is now true for gc, new and launch. Add a `WH_NO_FETCH=1` note under "Base policy".
- `docs/demo.cast:9, :14`: hand-edit the copy (`copied 1 file`; the Next block without `#` comments), or re-record.
- Completions (all three): status gains `--json --human`; fish gains `--dry-run` for launch. Do **not** add the deprecated aliases or `--force`.
- `CHANGELOG.md [Unreleased]`: Fixed (F1, F2, F5, F7, F8-gates, F10, F13, F19, F20, F21); Added (`status --json`, stdout identifiers for merge/gc/init, `help <cmd>`); Deprecated (`create`, `run`, `land`, `prune`, `gc --force`).

**R2 additions to B7** (ownership gains `docs/DESIGN.md`):
- **Glossary (R423, critic `unmentionedRules[42]`):** a `## Glossary` section in `docs/DESIGN.md`. Each noun gets its meaning and identity (accepted selector forms; the first is the stdout identifier), and the list names banned synonyms. Nouns: *worktree* (identity: absolute path, as printed by `new`), *main checkout*, *linked worktree*, *branch*, *default branch*, *base* (the ref `new`/`merge` branch from: `<remote>/<default>` or `<default>`, per `HARNESS_BASE_POLICY`), *merge gate*, *busy marker*, *port offset*, *`.harnessrc` setting*. Banned in copy, option names and positional names: "flag" (say "option", R060), "trunk", and "session" meaning a worktree. README/SKILL copy touched in this unit uses these terms.
- **R466 / F38:** README.md:245 becomes `Global options: --cwd <DIR> (run as if started in <DIR>), --dry-run, --no-color, -v/--version.` Completions: bash `:12` also skips `--cwd <DIR>`, `:20` offers `--cwd --dry-run --no-color --help --version` (drop `-C`); zsh and fish get the same option set. `-C`/`-V` stay unadvertised whatever D-R2-1 decides.
- **R102/R093:** README commands table (:237-243) and SKILL.md:34-40 use `<BRANCH>`, `[-- <COMMAND> [<ARG>]...]`.
- **F37/F39:** `docs/demo.cast:37-38`: `✓ Removed <full path> [add-auth] — branch 'add-auth' preserved` and `Remaining worktrees` (no colon). Hand-edit or re-record.
- **Install section from U-B8's PR body (F22, F27, F31, F32, F33, F35):** README.md:146-159 gains `sh install.sh --help`, the `--prefix <DIR>` form (if D-R2-3 adds it), `WORKTREE_HARNESS_REPO` and `WORKTREE_HARNESS_REF` (default, empty means default, read once per run, not persisted), "a relative prefix is taken from the current directory", the guidance variable (D-R2-5), and an uninstall command block that replaces "delete those two paths" (:158). The old wording could be read as deleting all of `~/.local/bin`. New text: `rm -rf ~/.local/share/worktree-harness ~/.local/bin/worktree-harness` (with `$WORKTREE_HARNESS_PREFIX` in place of `~/.local` if overridden), plus `brew uninstall worktree-harness` for Homebrew installs.
- **CHANGELOG:** Added (`--cwd`, `-v`, `status --fields`, install.sh `--help`/`--prefix`/`WORKTREE_HARNESS_REF`, guidance variable); Fixed (F22–F25, F27, F28, F30–F35, F37, F39); Deprecated (`-C`, `-V`, if D-R2-1 says so).

**R2b additions to B7** (ownership gains `docs/THREAT_MODEL.md`):
- **Threat model (F58).** Docs only, five edits in `docs/THREAT_MODEL.md`:
  1. `:18` WRITES row: `repo · $HARNESS_WORKTREE_HOME · $PREFIX + a temp dir (install)`, keeping the box alignment.
  2. `:20` NETWORK row: add `git clone (installer, outside a checkout only)`.
  3. `:32` heading: `At runtime, no network beyond git fetch, plus whatever the install/setup commands you configured do.` `lib/cmd_new.sh:81` evals the install command, so a carve-out for the installer alone would leave the claim false.
  4. `:36`: end with `…$PREFIX at install time, plus the installer's temp dir described below.`
  5. New bullet: `The installer. Run as a file from a checkout, install.sh uses that checkout and clones nothing. Otherwise it runs git clone --depth 1 from WORKTREE_HARNESS_REPO (default: the GitHub repo) into a mktemp -d directory and removes that directory on exit, including after a failure or Ctrl+C. The cloned code is what gets installed, so point that variable only at a source you trust.`
  The verifier's "a failed or interrupted install leaves it behind" is true only until U-B8 lands B8-18, so the text above describes the code as of this PR. `SECURITY.md:15` invites reports against these claims, so they need to stay accurate. C5 edits `:32` again later (serial).
- **Install variables (F54).** The README install section (near :158) and the install.sh header (:7-9) both gain the same facts. `WORKTREE_HARNESS_PREFIX`: install root, default `$HOME/.local`. `WORKTREE_HARNESS_REPO`: clone URL, used only on the clone path. For both: empty is treated as unset, and each is read once per run and never persisted. Precedence is `--prefix`, then the variable, then the default (D-R2-3). A custom prefix has consequences to state: re-running without it installs a second copy under `~/.local`, and the uninstall and shell-integration paths (README.md:158, :187) must use the chosen prefix. One sentence separates the two prefixes: `WORKTREE_HARNESS_*` are environment variables read by install.sh and the shell integration; `HARNESS_*` are `.harnessrc` settings, and exporting those in `lib/config.sh:20-33` has no effect because `wh_load_config` resets them before sourcing the file. These variables stay out of `worktree-harness --help`, because they affect only install.sh.
- **Offers (F48, if D-R2-13 is (a)).** README.md:197-198 gains the exact zsh `fpath` and fish copy steps, which exist only at install.sh:52 today (measured by the verifier: `rg fpath`). README.md:187 gains the bash and fish integration paths next to zsh. The installer stops being their only source before it stops printing them.
- **Truncated download (F56).** Add a second form next to README.md:149 that downloads to a file and runs it only if curl succeeded. Do not replace the existing line.
- **Upgrade path (F52, if D-R2-14 is (a)).** README.md:158 gains: re-running the installer is the upgrade path, and Homebrew users run `brew upgrade`. Reconcile this with `SECURITY.md:10`, which says only the latest released tag receives fixes.
- **Completions.** `status` gains `--json` only; `--human` stays out (B3-1 R2b). This overrides the round-1 line above.
- **Exceptions (R422).** A `## Exceptions` section in `docs/DESIGN.md` lists each with rule, reason, user impact and test: R313 (no wall-clock bound on `git clone`; stock macOS has no `timeout` and `CONTRIBUTING.md:8` forbids a dependency; `ssh://` stays unbounded), R156 (argv target required only on the destructive branch, C7), R086 (`worktree-harness <v>` bytes, D-R2-17), R438 (`--porcelain`, `--human`, D-R2-16), plus any exception D-R2-13, D-R2-15 or D-R2-18 selects.
- **CHANGELOG:** Fixed adds F41, F43, F45, F46, F48, F50–F52, F55, F56, F58. Added gains install.sh `--json` (if D-R2-15 is (a)).

Size: **~70 LOC** (estimated). **R2:** +~60 = **~130 LOC** (estimated). **R2b:** +~45 = **~175 LOC** (estimated).

### B8 (Round 2): `install.sh` + `test/install.bats` (new). Owns `install.sh`, `test/install.bats`, `.github/workflows/ci.yml`, `CONTRIBUTING.md:21,30`, `.github/PULL_REQUEST_TEMPLATE.md:7`

Runs in parallel with U-B1..U-B6 (file-disjoint). install.sh stays **POSIX sh**: no arrays, `local`, `[[ ]]` or `printf %q`. Under `curl | sh`, stdin is the script, so nothing may read stdin. **Compatibility contract for this unit:** the zero-argument run used by `ci.yml:60-61` and README.md:149/:155 keeps exit 0, the `$PREFIX/share/worktree-harness` layout, the `$PREFIX/bin/worktree-harness` symlink, and its current streams. Moving lines between streams is C6. Callers (measured with `git grep -n install.sh`): `ci.yml:60` (zero args; ignores stdout; then `:61` runs `--version`), README.md:149/:155 (human), CHANGELOG.md:44 and lib/compat.sh:27 (prose only). No test under `test/` runs it.

**R2b split.** With F41–F58 the unit would exceed the 500-LOC ceiling (Section 6.4), so U-B8 keeps the safety core: rows 1–5, 7, 13, 14 and the new rows 15–20. Rows 6 and 8–12 move to U-B10 (Section B10), which fires when U-B8 merges. Corrections to any row are inline below, marked **R2b**.

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R012 R081 R083 R064 R055 R337 R086 R023 R102 R436 R091 R100 (F22) | install.sh:10-12 | Add the parser directly after `set -eu`, before `REPO_URL`/`PREFIX`, `SELF_DIR`, clone, rm, cp and ln, so help and errors do no work and need no network. Follow F22's refinedFix with three corrections. (a) The value hint is `--prefix <DIR>` (R102/R436), not `--prefix DIR`. (b) Help sections are `Usage:` (`sh install.sh [options]`) plus a one-line summary, `Options:` (`-h, --help`; `--prefix <DIR>` with "(default: $WORKTREE_HARNESS_PREFIX, else ~/.local)"), `Examples:`, `Notes:` (the environment variables with precedence and empty-value behaviour; the piped form), `Learn more:`. (c) Usage errors use the A.1 layout: `Unknown option <x> for install.sh.`, a blank line, `See all options:`, `    sh install.sh --help`, exit 2. Note: the main CLI still exits 1 for usage errors until C1, while install.sh has no prior contract for argv, so it uses 2 from the start. `--` ends options; any leftover positional gives `Unexpected argument <x> for install.sh.` and exit 2. `--version` follows D-R2-2; the recommended (a) treats it as unknown and adds `To see the installed version, run:` / `    worktree-harness --version`. `--prefix` follows D-R2-3; with the recommended (a), `--prefix` beats the env var (R073) and line 13 becomes `PREFIX="${OPT_PREFIX:-${WORKTREE_HARNESS_PREFIX:-$HOME/.local}}"`. Examples (R101): `    sh install.sh`, `    sh install.sh --prefix <DIR>`, `    curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh \| sh -s -- --prefix <DIR>`. **Parse-only (R100):** `__WORKTREE_HARNESS_PARSE_ONLY=1` exits 0 right after the parse; it is internal and never in help. **R2b (F41):** B8-15 adds the help-first scan, the `help` arm and the empty-value refusal. The parser sits inside `main()` (B8-16). D-R2-2's recommendation changes to (b); see Section 8. |
| 2 | R005 R470 R013 R001 R043 R011 (F23) | install.sh:17-21 | Use the local tree only when `$0` is a real file named `install.sh` (`case "$0" in */install.sh\|install.sh) [ -f "$0" ] && …`), per F23's refinedFix; never fall back to `$PWD`. Under `curl \| sh`, `$0` is `sh` and the script always clones. Before any write, print the resolved source on stderr: `Installing from <SRC> (local checkout)…` or `Installing from <URL shown> at <short commit>…` (R001; progress copy per R220). No `--from`/`WORKTREE_HARNESS_SRC` option is planned. **R2b correction (F45):** the commit isn't known before the clone, so `at <short commit>` contradicts "before any write". The clone branch prints `Installing from <URL shown>…` before `mktemp` (:24), the checkout branch prints `Installing from <SRC> (local checkout)…` before the first write, and the commit moves to the receipt (B8-10). F45's `Source:` label isn't used because a label takes no trailing colon (R183). `curl \| /bin/sh` already clones, because `dirname /bin/sh` is `/bin` (measured by the verifier); the bug needs a bare shell name, which is the documented form. |
| 3 | R015 R002 R146 R148 R034 (F24) | before install.sh:32 | Resolve both paths with `CDPATH= cd -P … && pwd -P`. Refuse when SRC is inside SHARE_DIR, SHARE_DIR is inside SRC, or `$SHARE_DIR/.git` exists: `Can't install into <SHARE_DIR>. It's the source checkout.`, a blank line, `Run the installer from another directory, or choose another prefix:`, `    sh install.sh --prefix <DIR>`. Exit 1 (Conflict); the trap (row 4) removes any temp clone. No y/N prompt: the consent tier is part of D-R2-4. |
| 4 | R351 R015 R335 R364 R416 R007 R318 R003 (F25) | install.sh:19, 24-38 | F25's refinedFix: `STAGE=""`, `OLD=""`, `SWAPPED=""` and a guarded `cleanup()` (`[ -n "$STAGE" ] && rm -rf "$STAGE"; [ -n "$CLEANUP" ] && rm -rf "$CLEANUP"; return 0`) on `EXIT`. **Not** `rm -rf "${TMP:?}"`, which fails under `set -u` on the checkout path (CI's path) because TMP is unset there; that also replaces F28's identical trap suggestion. INT, TERM and HUP each run cleanup and exit 130/143/129. Before the swap starts they print `Canceled. The existing install at <SHARE_DIR> is unchanged.`; after, they print what was replaced (R336: report only confirmed facts). Stage with `mktemp -d "$PREFIX/share/.worktree-harness.XXXXXX"` (same filesystem, so `mv` is a rename), then cp and chmod there. Swap with `mv "$SHARE_DIR" "$OLD"`, then `mv "$STAGE" "$SHARE_DIR"`, restoring `$OLD` and exiting 1 with `Couldn't replace <SHARE_DIR>. The previous install was restored.` if the second mv fails. Link only after the swap; remove `$OLD` last. Drop line 38, since the EXIT trap now cleans up. **R2b correction (F43, F51):** this row can't land as written. Without `mkdir -p "$PREFIX/share"` first, the stage's `mktemp -d` fails on `ci.yml:60`'s empty prefix. `mktemp -d` makes 0700, which would change the install dir's mode. `$OLD` must be a path inside a temp directory, because `mv` onto an existing directory nests. B8-17 fixes those three, and B8-18 replaces the cancel messages and the cleanup. |
| 5 | R074 R003 R017 R069 R079 (F27) | install.sh:13, after :36 | After line 13: `case $PREFIX in /*) ;; *) PREFIX="$(pwd)/$PREFIX" ;; esac`, before lines 14-15 build SHARE_DIR/BIN_DIR, so the link target on :36 is absolute. After linking, check `[ -x "$BIN_DIR/worktree-harness" ] \|\| { echo "Can't verify $BIN_DIR/worktree-harness. It doesn't resolve to $SHARE_DIR/bin/worktree-harness." >&2; exit 1; }` before any success line. Empty values follow D-R2-7; the recommended (a) documents "empty means the default" in the header :7-9, `--help` Notes, and README (B7). **R2b (F46):** the line is `*) PREFIX="$(pwd)/${PREFIX#./}" ;;`, and the `[ -x ]` check runs before any receipt. B8-19 adds `--` to the clone; C8 holds the explicit `~` and `-*` rejections. |
| 6 | R275 R277 R285 R292 R337 R339 R017 R014 R313 R019 (F28) | install.sh:23, 27 | F28's refinedFix (1) and (3): `GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 clone --depth 1 -q … 2>"$TMP/clone.err"`. On failure: `Couldn't clone <URL shown> from <host>. <first fatal: line, redacted>.`, a blank line, `Check the URL and your network or proxy, or install from a checkout instead:`, `    git clone <URL shown> && sh ./worktree-harness/install.sh`, exit 1. Line 23 becomes `Can't install worktree-harness without git.` with the same recovery; exit stays 1 (R337: a missing prerequisite is operational). Proxy and CA variables are left to git (R292). The refinedFix's step (2) trap is replaced by row 4. **R2b correction (F44; moves to U-B10):** four parts of this row contradict a rule, and B10-1 replaces them. `exit 1` breaks Wave B's no-exit-change rule; git's 128 stays until C8. `GIT_TERMINAL_PROMPT=0` removes typed credentials, a contract change that also moves to C8. The `fatal:` line in the headline breaks R278/R297; it becomes an attributed Detail row. The chained `git clone … && sh …` recovery breaks R105; it becomes one command. |
| 7 | R079 R355 R018 (F33) | install.sh:7-9, 12, 23, 26 | Keep the name `WORKTREE_HARNESS_REPO`; renaming would silently ignore existing users (R079). Document it in the header and `--help` Notes as "git URL to clone when not run from a checkout (default …; empty or unset uses the default; read once per run, not persisted)". Add `REPO_URL_SHOWN=$(printf '%s' "$REPO_URL" \| sed 's#//[^@/]*@#//#')` and use it in every printed line, including row 6's fatal line (pipe it through the same sed). Only `git clone` sees the raw URL. **R2b correction (F55):** that sed leaks part of a password containing `@`: `https://user:p@ss@host/repo.git` prints `https://ss@host/repo.git` (measured with `sed` on the sample string). Use `sed 's#://[^/]*@#://#'`, which prints `https://host/repo.git` and leaves `git@github.com:a/b.git`, `https://host/a@b/r.git` and `/local/path@1/repo` unchanged (measured). Credentials in a query string aren't covered. **F54:** the header and `--help` Notes also state empty-value behaviour and non-persistence for `WORKTREE_HARNESS_PREFIX`. |
| 8 | R004 R105 R103 R220 R236 R237 (F30) | install.sh:41-54 | Replace the block with one `Next steps:` list, following F30's refinedFix: a POSIX `shq()` single-quote helper (sed-based; POSIX sh has no `printf %q`). The PATH step comes first when BIN_DIR is not on PATH: `Put worktree-harness on your PATH:` / `    export PATH=<shq BIN_DIR>:"$PATH"`; `WH` is then the quoted absolute path, otherwise `worktree-harness`. Then `Set up a repository:` / `    cd <REPO>` / `    $WH init` (init fails outside a repo, cmd_init.sh:12); `Create a worktree:` / `    $WH new <BRANCH>` (placeholder per R102 and the glossary, not `<NAME>`); and shell integration and completion lines **only for the detected `$SHELL`**. The block stays on the current stream (stdout) until C6. R099 is dropped: no short options are printed. **R2b (moves to U-B10):** B10-3 adds the PATH states and state checks. |
| 9 | R238 R240 R241 (F31) | the row 8 block | The PATH step is required recovery and always prints. The shell-integration and completion offers print only when `[ -t 1 ]` (the stream they are on until C6; then `[ -t 2 ]`), `CI` is unset, and the guidance variable (D-R2-5) is unset. "Set up a repository" and "Create a worktree" are next steps: shown every time (R235) unless guidance is disabled (R238), per D-R2-8's recommended (a). **R2b correction (F48, R113, R240; moves to U-B10):** `[ -t 1 ]` is the wrong test. R113 makes a run non-interactive when stdin or stderr isn't a TTY, and R240 limits offers to interactive mode, so `curl \| sh` (stdin is the script) never qualifies. The gate is `[ -t 0 ] && [ -t 2 ]`, `CI` unset and guidance on, under D-R2-13's recommended (a). Option (b) keeps them for `curl \| sh` with a recorded R422 exception. |
| 10 | R021 R180 R472 (F32) | install.sh:27, 38-40 | Before cleanup, read `VERSION=$(sed -n 's/^WH_VERSION="\(.*\)"$/\1/p' "$SRC/lib/common.sh")` (read, never source) and `COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null \|\| true)`. Add a pin, `WORKTREE_HARNESS_REF` (tags `v0.1.0` and `v0.2.0` exist, measured with `git tag -l`): `git clone --depth 1 --branch "$REF"` when set. The receipt names the immutable commit next to a mutable pointer, e.g. `0.2.0 (commit abc1234, from main)` (R472). R371 and the "install marker" part of the finding are dropped here; the marker belongs to C7. **R2b (moves to U-B10):** B10-4 adds the fresh, replaced and unchanged states. `WORKTREE_HARNESS_REF` stays an opt-in pin; the default ref is D-R2-14. |
| 11 | R182 R183 R185 R186 R205 R231 R220 R181 (F34) | install.sh:26, 31, 40, 52 | Pick the glyph mode once: rich when `[ -t 1 ]` and `TERM` is not `dumb` (fd 1 until C6, then fd 2). Rich uses `✓`, `…` and a blank progress gutter (D-R2-6); plain uses no glyph and `...`. Progress lines: `Cloning <URL shown>…` and `Installing to <SHARE_DIR>…`. The receipt is `✓ Installed worktree-harness <VER>`, with contiguous rows `  Path      <BIN_DIR>/worktree-harness` and `  Version   <VER> (commit <C>)`. In plain mode it is one sentence at column 0: `Installed worktree-harness <VER> to <path>.` The `·` separator goes with the row 8 rewrite. **R2b correction (F49, R181; moves to U-B10):** rich rows use the 16-character label column, values at column 18, through one helper: `printf '  %-16s%s\n'`, not the hand-padded rows above. Test `${TERM:-}`, because `set -u` is on and `TERM` may be unset in CI. The helper stays inside install.sh, since `curl \| sh` has no `lib/` to source. `:43`, `:46`, `:51` and `:54` change in the same pass (B10-3), so the copy isn't left half-converted. No check on `NO_COLOR` (R207). |
| 12 | R004 R021 R007 (F35) | the row 8 block | The last next step, which is optional and so respects the guidance variable: `Uninstall later by removing both paths:` / `    rm -rf -- <shq SHARE_DIR> <shq BIN_DIR/worktree-harness>`. That is one command; `rm -rf` on the symlink removes the link, not its target. It replaces the verdict's `uninstall:   … && …` (label with a colon plus a chained command, R183/R105). README via B7. `--uninstall` is not planned; if added later it needs R002/R148's preview. |
| 13 | R390 R391 R397 R399 R402 R392 R100 (F36) | `test/install.bats` (new) | Every test uses its own `$BATS_TEST_TMPDIR` prefix (absolute), `TMPDIR="$BATS_TEST_TMPDIR/tmp"` (so leaks are observable), and a local fixture `WORKTREE_HARNESS_REPO="file://$BATS_TEST_TMPDIR/fixture.git"` built with `git init` and a commit of `bin lib share`. Nothing touches the network or `$HOME`. Each assert lands in the same commit as the behaviour it covers (see the test table). **R2b (F57):** see B8-20. |
| 14 | gates | ci.yml:23, :58-61; CONTRIBUTING.md:21, :30; PULL_REQUEST_TEMPLATE.md:7 | Add `shellcheck -s sh install.sh` to the lint step and the docs' shellcheck line. In the install job, add `WORKTREE_HARNESS_PREFIX="$RUNNER_TEMP/p2" sh ./install.sh --help >/dev/null && test ! -e "$RUNNER_TEMP/p2"`. Keep `:60-61` unchanged. **R2b correction (F57):** the lint is its own CI step, not part of the `:23` list, because `.shellcheckrc:8` sets `shell=bash` and `-s sh` would then apply to every file. `CONTRIBUTING.md:30` is reworded, since "the bash sources" no longer covers it. |

Tests (`test/install.bats`, new; `bats_require_minimum_version 1.5.0`):

| Test name | Assertion |
|---|---|
| `fresh install from the checkout` (current contract) | `WORKTREE_HARNESS_PREFIX="$P" run sh "$WH_ROOT/install.sh"`: status 0; `[ "$(readlink "$P/bin/worktree-harness")" = "$P/share/worktree-harness/bin/worktree-harness" ]`; bin, lib and share present; `"$P/bin/worktree-harness" --version` exits 0 |
| `reinstall replaces the tree` | stray file in `$P/share/worktree-harness` is gone after a second run; status 0 |
| `--help does no work` / `-h is the same` (F22, R392) | status 0, `$output` has `Usage:` and `--prefix <DIR>`, `[ ! -e "$P" ]`; `-h` output equals `--help` output |
| `an unknown option exits 2 and names it` (F22) | `run sh install.sh --bogus`: status 2, `*"Unknown option --bogus for install.sh."*`, `*"See all options:"*`, `[ ! -e "$P" ]` |
| `--version follows D-R2-2` | (a): status 2 and `*"worktree-harness --version"*`; (b): prints only the version. **R2b:** under (b), also `the installer version constant matches lib/common.sh`, comparing the constant with `sed -n 's/^WH_VERSION="\(.*\)"$/\1/p' "$WH_ROOT/lib/common.sh"`, and `--version` under a piped run from an empty cwd prints the same value with `$TMPDIR` empty (no clone, R012/R083) |
| `--prefix beats WORKTREE_HARNESS_PREFIX` (if D-R2-3 a) | env points at `$P1`, `--prefix "$P2"`: install lands in `$P2`, `[ ! -e "$P1" ]` |
| `every --help example parses` (R100) | extract `Examples:` lines; rewrite `curl … \| sh -s --` to `sh -s -- … < "$WH_ROOT/install.sh"`; `<DIR>`→`$P`; run each with `__WORKTREE_HARNESS_PARSE_ONLY=1`: all status 0, `[ ! -e "$P" ]` |
| `the piped --help example works without a checkout` (R100, F22) | `cd "$BATS_TEST_TMPDIR/empty" && sh -s -- --help < "$WH_ROOT/install.sh"`: status 0 |
| `piped install ignores a decoy bin/worktree-harness in the cwd` (F23) | cwd has `bin/worktree-harness` printing `decoy`; `sh -s < install.sh` with the fixture repo: installed `--version` output is the fixture's, never `decoy`; stderr names the fixture URL as the source |
| `refuses to install over its own source checkout` (F24) | `git clone -q "file://$WH_ROOT" "$P/share/worktree-harness"`; `run sh "$P/share/worktree-harness/install.sh"` with `WORKTREE_HARNESS_PREFIX="$P"`: status 1, `*"It's the source checkout."*`, `.git` and `install.sh` still present |
| `a failed copy keeps the previous install` (F25) | `[ "$(id -u)" = 0 ] && skip`; install once; then a source copy with `chmod 000` on one lib file: status ≠ 0, the previous `$P/bin/worktree-harness --version` still works, no `$P/share/.worktree-harness.*` left |
| `a failed clone exits 1, says why, leaks nothing` (F28, F25) | `WORKTREE_HARNESS_REPO=file:///nonexistent`, piped: status 1, stderr `*"Couldn't clone"*`, `[ ! -e "$P/bin/worktree-harness" ]`, `$TMPDIR` empty. **R2b:** moves to `test/install_output.bats` and asserts `-ne 0` until C8 flips it to 1 |
| `credentials in the repo URL are never printed` (F33) | `WORKTREE_HARNESS_REPO=https://user:s3cret@127.0.0.1:9/x.git` (localhost port 9, refused at once, no external network), piped: status 1, output and stderr lack `s3cret`. **R2b (F55):** asserts `-ne 0` until C8, and repeats with `user:p@ss@127.0.0.1:9`, asserting the output lacks `ss@` |
| `a relative prefix installs a working link` (F27) | `cd "$BATS_TEST_TMPDIR"; WORKTREE_HARNESS_PREFIX=rel run sh "$WH_ROOT/install.sh"`: status 0, `"$BATS_TEST_TMPDIR/rel/bin/worktree-harness" --version` exits 0 |
| `optional offers are hidden in CI` (F31) | `CI=1`: output lacks `shell integration` and `completions`; has the PATH step when `$P/bin` is not on PATH |
| `the printed PATH command works for an awkward prefix` (F30) | prefix `"$BATS_TEST_TMPDIR/a b'c"`: extract the `export PATH=` line; `sh -c "<line>; command -v worktree-harness"` prints `$P/bin/worktree-harness` |
| `the receipt names the version and commit` (F32) | `*"$(sed -n 's/^WH_VERSION="\(.*\)"$/\1/p' "$WH_ROOT/lib/common.sh")"*`; with the fixture, `*"commit "*` |
| `install.sh is POSIX` (gate) | `sh -n install.sh`; `dash -n install.sh` when dash exists |
| `streams as of Wave B` | `run --separate-stderr`: the receipt is on `$output`; errors (unknown option, clone failure) are on `$stderr`. C6 flips this test |

Size: install.sh ~+170 changed (54 → ~200 lines), tests ~170, ci.yml and docs ~10 = **~350 LOC** (estimated by counting each row's refinedFix lines; tests at ~9 lines per case). **R2b:** rows 6, 8–12 and four test cases move to U-B10 (about −125); the rows and tests below add about +235 = **~460 LOC** (estimated, same method).

### B8 Round 2b additions (same unit, same files, plus `test/install_helper.bash` (new))

Implement row 16 first, because every other change then lands inside `main()`.

| # | Rules | Site | Change |
|---|---|---|---|
| 15 | R083 R081 R012 R066 R074 R304 R393 R411 R441 R064 (F41) | B8-1's parser | **Help first.** Before the parse loop: `for a do case "$a" in --) break ;; -h\|--help) usage; exit 0 ;; esac; done`, then `[ "${1:-}" = help ] && { usage; exit 0; }`. So `--bogus --help` shows help (R083) and `sh install.sh help` works (R081). F41's plain left-to-right loop would exit 2 on the first, and its "extra positional exits 2" would reject the second. **`--prefix`.** `--prefix <DIR>` and `--prefix=<DIR>` both parse. A missing or empty value gives `Option --prefix needs a value.`, exit 2, because an empty `OPT_PREFIX` must never reach line 32: an empty prefix would make it `rm -rf /share/worktree-harness`. **Guessed options.** `--dry-run`, and `--force`/`--yes` before C7, are unknown options (exit 2), never ignored (R064, R437). **`HOME`.** Compute the default after the parse and guard it. With `HOME` unset and no prefix, print `Can't pick an install location. HOME isn't set.`, a blank line, `Install to a named directory:`, `    sh install.sh --prefix <DIR>`, exit 2. Today `set -u` aborts at :13 with a raw shell error. |
| 16 | R003 R015 (F56) | install.sh:10-54 | Keep lines 1–10, put helpers (`usage`, `cleanup`, `say`, `fail`) above `main`, wrap the rest in `main() { … }`, and make the last line exactly `main "$@"`, with a one-line comment saying why. A truncated `curl \| sh` body then fails to parse or defines functions only (measured by the F56 verifier on a wrapped copy: every byte prefix ending inside the body fails `sh -n` and `dash -n`). Do not write `main "$@" \|\| …` or `if main …`: either disables `set -e` inside the function, so the unguarded `git clone` and `cp` would stop aborting. No `local`: it isn't POSIX, and B8-14's `-s sh` catches it. `$0` is unchanged inside a function (measured by the verifier under `/bin/sh`, `/bin/dash`, `/bin/bash`), so B8-2 still works. **Residual gap under R003:** a truncation before `main() {`, or an empty body, still exits 0 with nothing installed and the old install intact. The script can't detect that from inside; B7 adds the download-then-run form. |
| 17 | R015 R302 R351 R399 (F43; amends B8-3, B8-4) | install.sh:20, 27-36 | **Validate before any write,** after SRC is set, on both source branches. Check `bin/worktree-harness`, `lib/common.sh` and `lib/compat.sh` (files; `bin/worktree-harness:61,63` source them unconditionally) and `share/` (directory). Collect every missing path, print them all on stderr with `$SRC`, and exit 1 (R302). **Overlap, physical paths, both directions:** B8-3's check first walks `$SHARE_DIR` up to its nearest existing directory, because `cd -P` fails on a path that doesn't exist yet, and it covers `PREFIX=$SRC`, which would otherwise put the stage inside `$SRC/share`. **Fresh prefix:** `mkdir -p "$PREFIX/share" "$BIN_DIR"` after validation and before `mktemp`. **Mode:** `chmod "$(umask -S)" "$STAGE"`. **Swap:** `OLD=$(mktemp -d "$PREFIX/share/.worktree-harness-old.XXXXXX")`, `mv "$SHARE_DIR" "$OLD/old"`, `mv "$STAGE" "$SHARE_DIR"`. This is two renames, so document the short window rather than calling it atomic. **Link:** `L=$(mktemp -d "$BIN_DIR/.worktree-harness.XXXXXX")`, `ln -s "$SHARE_DIR/bin/worktree-harness" "$L/link"`, `mv -f "$L/link" "$BIN_DIR/worktree-harness"`, `rmdir "$L"`. If removing the old tree fails after a successful swap, warn; the install still succeeded. |
| 18 | R007 R294 R335 R336 R342 R416 R003 (F51; amends B8-4) | install.sh:19, 24-27, 38 | **One phase variable, one EXIT handler.** `PHASE=before`, then `swapping` around the two renames, `swapped` after the second, `done` after the link. `on_exit` saves `$?` and runs `trap - EXIT; set +e`. When `PHASE=swapping` and `$SHARE_DIR` is absent, it first restores `$OLD/old`; if that restore fails, it keeps `$OLD` and names it, because that directory now holds the only copy of the previous install. It then removes `$STAGE`, `$L`, `$CLEANUP` and `$OLD` (each checked non-empty) and warns on a failed removal. It reports by status rather than from the signal handler, because a child killed by SIGINT can trip `set -e` first. On status 129, 130 or 143 it prints, by phase: `before`: `Canceled.` and `Nothing was changed.`; `swapping`: `Canceled.` and `The previous install was restored.`; `swapped`: `Stopped waiting.`, `<SHARE_DIR> was replaced, but <BIN_DIR>/worktree-harness wasn't updated.` and the rerun command; `done`: nothing extra. It exits with the saved status, so a failed temp removal can't change a result (R342). **Signals:** `on_signal` resets the INT, TERM and HUP traps first, so a second Ctrl+C stops at once (R335), kills `$CHILD` if set, and exits 130, 143 or 129. **Clone as a bounded child:** `git clone … & CHILD=$!; rc=0; wait "$CHILD" \|\| rc=$?; CHILD=""`. With a plain foreground clone, TERM to the shell alone waits for the clone to end (measured by the F51 verifier on a stand-in child: 3 s against 1 s). A background child ignores SIGINT in a non-job-control shell, so the `kill` is required. **The :24/:25 gap:** `CLEANUP=$(mktemp -d); TMP=$CLEANUP`. Delete :38, whose failing `rm` turns a completed install into a non-zero exit with no receipt today. |
| 19 | R013 R071 (F46, compatible part) | install.sh:27 | `git clone --depth 1 -- "$REPO_URL" …`, so a dash-leading value can't parse as a git option. It has no demonstrated impact today (eight dash values all failed with exit 128 or 129, measured by the verifier in scratch) and the value is the user's own environment, so this is a clarity fix, not a security one. Newline rejection isn't planned: an absolute prefix containing a newline installs correctly today. |
| 20 | R390 R397 R399 R402 (F57; amends B8-13) | `test/install.bats`, `test/install_helper.bash` | The helper holds the `file://` fixture (a temp repo with copies of `bin/`, `lib/`, `share/`, identity set by local `git config` as `make_repo` does) and a setup that points both `HOME` and `WORKTREE_HARNESS_PREFIX` at temp paths, so `~/.local` is never touched. `test/install_output.bats` and `test/install_json.bats` load it read-only. Capture streams with `run --separate-stderr`. `bats test/` (`ci.yml:39`, `:47`) picks all three files up on both OSes and under bash 3.2. Do not add install.sh to `test/bashism.bats`' bash-only checks; the `sh -n` test is the right one. |

Tests appended to `test/install.bats`:

| Test name | Assertion |
|---|---|
| `help wins over an earlier unknown option` (R083, F41) | `run --separate-stderr sh install.sh --bogus --help`: status 0, `$output` has `Usage:`, `[ -z "$stderr" ]`, `[ ! -e "$P" ]` |
| `install.sh help prints the same help` (R081, R393) | `[ "$(sh install.sh help)" = "$(sh install.sh --help)" ]`; status 0; `[ ! -e "$P" ]` |
| `-- ends help scanning` (R066) | `sh install.sh -- --help`: status 2, `*"Unexpected argument --help for install.sh."*`, `[ ! -e "$P" ]` |
| `an empty --prefix is a usage error` (F41) | `--prefix=` and a trailing `--prefix`: status 2, `*"Option --prefix needs a value."*`, nothing written |
| `--dry-run is refused, not ignored` (R064, R441) | status 2, `*"Unknown option --dry-run for install.sh."*`, `[ ! -e "$P" ]` |
| `unset HOME without a prefix names the fix` (F41) | `env -u HOME -u WORKTREE_HARNESS_PREFIX sh install.sh`: status 2, `*"HOME isn't set"*`, `*"--prefix <DIR>"*` |
| `a truncated download changes nothing` (F56, R003) | install once. For every 10th line count inside `main`: `head -n "$n" install.sh \| WORKTREE_HARNESS_PREFIX="$P" sh` from an empty cwd. After each, the share dir inode (`ls -di`) and `"$P/bin/worktree-harness" --version` are unchanged and no `$P/share/.worktree-harness*` exists |
| `a source missing files lists them all and keeps the old install` (F43, R302) | install once; `WORKTREE_HARNESS_REPO` points at a fixture holding only `bin/`, piped from an empty cwd: status 1; `$stderr` names `lib/common.sh`, `lib/compat.sh` and `share`; the old `--version` works |
| `a new install dir follows the umask` (F43) | `umask 022`, install: `ls -ld "$P/share/worktree-harness"` starts with `drwxr-xr-x` |
| `a prefix inside the source is refused` (F43) | `WORKTREE_HARNESS_PREFIX="$SRC"` with a copied checkout at `$SRC`: status 1, `*"It's the source checkout."*`, `[ ! -e "$SRC/share/worktree-harness" ]` |
| `piping from inside the install dir keeps a working install` (F43, F45) | install once; `cd "$P/share/worktree-harness"`; piped with the fixture: status 0; `"$P/bin/worktree-harness" --version` works |
| `TERM during the clone exits 143 fast and cleans up` (F51, R335) | `git` shim in `$BATS_TEST_TMPDIR/bin` that runs `exec sleep 30`. Start the piped install in the background from an empty cwd, poll until a temp dir appears in `$TMPDIR`, `kill -TERM`, `wait` gives 143 in under 5 s by `date +%s`. `$TMPDIR` is empty; stderr has `Canceled.` and `Nothing was changed.`. HUP gives 129 the same way. Use TERM and HUP, not INT, because background jobs in non-interactive shells ignore SIGINT |
| `a failed temp removal warns and keeps exit 0` (R342) | `rm` shim that fails for paths under `$TMPDIR`, piped with the fixture: status 0, `"$P/bin/worktree-harness" --version` works, stderr has a warning naming the temp path |
| `piped install clones the fixture` (F57) | from an empty cwd with the fixture: status 0; the installed tree holds the fixture's marker file. CI never runs this path, because `ci.yml:60` finds the checkout |
| `missing git fails before any write` (F57) | `PATH` holds links to `dirname`, `mktemp` and `sh` but no git, piped from an empty cwd: status 1, `$stderr` names git, `[ ! -e "$P" ]` |
| `a failed clone over an existing install keeps it` (F57) | install once; `WORKTREE_HARNESS_REPO=file:///nonexistent`, piped: status non-zero (git's own code until C8), the old `--version` works |

### B10 (Round 2b): install.sh failure copy, next steps and receipts. Owns `install.sh` (fires after U-B8 merges), `test/install_output.bats` (new)

Numbered B10 and B11 so that B9's references stay stable. This unit carries B8 rows 6, 8, 9, 10, 11 and 12 as corrected there, plus the rows below. It keeps B8's compatibility contract: zero-argument exit 0, layout, link, current streams, no non-zero exit code changed. Lines that don't exist today can go to stderr; existing lines stay on stdout until C6.

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R003 R019 R275 R278 R292 R297 R313 R018 R355 (F44; replaces B8-6's copy) | install.sh:26-27 | The block below. It keeps git's own stderr out of the headline, takes the first `fatal:` or `error:` line rather than git's last line, redacts it, and passes 128+n through to the signal path. Git's SSH failure usually ends with an advice line, so the last line is the wrong one. F44's verifier chose the last `fatal:`; the first is used here because, for a missing local path, the last is the generic `Could not read from remote repository.` while the first names the path (measured with the toy `/tmp/cli-bp/wh_r2b_probe.sh`). `</dev/null` stops the clone reading the rest of a piped script. **Known limits, recorded under R422 by B7:** the low-speed settings cover HTTP(S) only, so an `ssh://` value stays unbounded; stock macOS has no `timeout` and `CONTRIBUTING.md:8` forbids a dependency, so R313's total limit is met for stalls only. `GIT_HTTP_LOW_SPEED_LIMIT` and `GIT_HTTP_LOW_SPEED_TIME` override the `-c` values on slow links. Round 2's 30 s becomes 60 s, the value F44's verifier probed. |
| 2 | R004 R275 R276 R277 R280 R282 R284 R285 (F50) | new `fail`; install.sh:23, 24, 33-36 | **Helper.** `fail <exit> <headline> [<detail>] [<instruction> <command>]` prints a blank line, `✗ <headline>` (plain: `Error: <headline>`), an optional `  Detail          <detail>` row, a blank line, `<instruction>:` and the command indented 4 spaces. It can't source `wh_err`, because `curl \| sh` has no `lib/` before the clone. **Preflight before the first write:** walk `$(dirname "$SHARE_DIR")` and `$BIN_DIR` up to their nearest existing directories. If `[ -w ]` fails, `Can't install to $PREFIX. <base> isn't writable.` with the detail `Nothing was changed.` and the recovery below. F50's `\|\| err "… isn't writable"` on each tool would guess the cause, since the failure could be a full disk (R275). **Mid-run failures use `Couldn't` with no invented cause,** and the tool's own stderr stays visible above. They follow B8-4's stage, not today's order, so F50's "the previous install was already removed" no longer applies: copy or chmod into the stage: `Couldn't copy files to <SHARE_DIR>. The previous install is unchanged.`; second rename: B8-4's `Couldn't replace <SHARE_DIR>. The previous install was restored.`; link: `Couldn't link <BIN_DIR>/worktree-harness. Files are in <SHARE_DIR>.`; `mktemp`: `Failed to create a temporary directory.` **`:23`:** `Can't clone <URL shown>. git isn't on PATH.`, then `Install git, then rerun the installer:`. **Recovery matches how the script started:** clone mode prints `curl -fsSL <install-url> \| sh -s -- --prefix <DIR>`; checkout mode prints `sh <shq SELF_DIR>/install.sh --prefix <DIR>`. Under D-R2-3 (b) the piped form is `curl … \| WORKTREE_HARNESS_PREFIX=<DIR> sh`; putting the variable before `curl` would set it on the wrong process. |
| 3 | R004 R103 R105 R212 R235 R236 R237 R238 R242 R307 (F48; extends B8-8) | install.sh:41-54 | **Paths stay exact.** Every line carrying a path uses `printf '%s\n'`, including :26, :43 and :51, because dash's `echo` alters a backslash in a path (measured by the verifier under sh and dash). `shq` round-tripped space, `"`, `$`, `'`, backslash and backtick in the verifier's probe. **Three PATH states from `command -v worktree-harness`,** replacing :41's literal match, which misreads an entry like `~/.local/bin/`. Compare physical parent directories (`pwd -P`), so a symlinked prefix isn't misreported. This copy resolves: use the bare name. Nothing resolves: `! worktree-harness isn't on PATH, so the command won't resolve. Add it:` and the indented export. Another copy resolves: `! worktree-harness resolves to <path>, not this install, so the bare command runs that copy.` Both warnings always print and ignore the guidance variable (R238, R242); in both, the list below uses the quoted absolute path. Plain mode prefixes `Warning: ` (R205). `Formula/worktree-harness.rb:26` confirms the Homebrew shadow case is reachable. **State checks,** each inside `if` so `set -e` can't fire: when the cwd isn't in a repo (guard on `command -v git`), print `cd <REPO>` first; when `.harnessrc` exists, omit `init`. `lib/cmd_init.sh:12-15` dies in both cases, so today's `&&` chain at :54 never reaches `new`. **Offers are real commands,** per D-R2-13: `source <shq path>`, `fpath=(<shq dir> $fpath)`, and a `cp` into the fish completions directory, showing only the detected `${SHELL:-}`'s lines. List the integration offer only after any PATH fix, because `share/shell/zsh.sh:8` says to source it after the command is on PATH. F48's `<PROJECT_DIR>` isn't used: `<REPO>` has no extra label (R102). |
| 4 | R003 R021 R033 R180 R326 (F52; extends B8-10, moves C7's receipt bullet here) | after validation, before the swap; install.sh:40 | Compute the state before anything is replaced. `read_version() { sed -n 's/^WH_VERSION="\(.*\)"$/\1/p' "$1" 2>/dev/null \|\| true; }`: read, never source, because `common.sh` is bash; match the assignment, not line 12; the `\|\| true` stops a missing file killing `X=$(…)` under `set -e`. `STATE=fresh` when `$SHARE_DIR` is absent, else `replaced`. `STATE=unchanged` only when both versions are non-empty and equal, `diff -r` finds `$SRC/bin`, `lib` and `share` identical to the installed tree, the installed dispatcher is executable, and `readlink "$BIN_DIR/worktree-harness"` equals `$SHARE_DIR/bin/worktree-harness`. Those last two stop a broken link reporting "already installed". A missing `diff` reads as "different" and takes the safe path. On `unchanged`, skip stage, swap and link, and don't exit early, or the temp clone leaks. **Receipt:** `unchanged`: `worktree-harness <VER> is already installed.`, exit 0. `fresh` and `replaced`: B8-11's receipt, plus for `replaced` a row `Replaced` with `<OLD>`; `<OLD> (different content)` when versions match, because `WH_VERSION` doesn't change between commits on main; `unknown version` when `<OLD>` is empty. New rows go to stderr with an explicit `>&2`. The PATH warnings still print on every state. Signed checksums aren't planned (R371 targets an upgrade command, and there is none). |
| 5 | R341 R016 R177 (F47, compatible part) | top of `main`; every status line | `trap '' PIPE` and `say() { ( printf '%s\n' "$*" ) 2>/dev/null \|\| :; }`, so a closed stream can't abort an install that has started. `set -e` kills a bare `echo` on a closed pipe, and ignoring SIGPIPE alone still dies (measured by the F47 verifier: pipestatus 141 0, then 1 0, in models of this script, not the script). The subshell is required: without it, macOS `/bin/sh` re-spilled stale buffered lines onto stdout (same model). This row keeps the stream; C6 moves `say` to stderr. It lands here, not in C6, because aborting mid-install on `\| head` is a bug independent of the stream contract. |

The clone block for row 1 (`fail "$rc"` keeps git's code until C8):
```sh
show_url() { printf '%s' "$1" | sed 's#://[^/]*@#://#'; }
rc=0
git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 clone --depth 1 -- "$REPO_URL" "$TMP/worktree-harness" \
  </dev/null >/dev/null 2>"$TMP/clone.err" &
CHILD=$!
wait "$CHILD" || rc=$?
CHILD=""
if [ "$rc" -ne 0 ]; then
  [ "$rc" -le 128 ] || exit "$rc"
  err=$(sed 's#://[^/ ]*@#://#g' "$TMP/clone.err")
  detail=$(printf '%s\n' "$err" | grep -E '^(fatal|error):' | head -n 1)
  [ -n "$detail" ] || detail=$(printf '%s\n' "$err" | grep . | tail -n 1)
  fail "$rc" "Couldn't clone $(show_url "$REPO_URL"). Nothing was changed." \
    "git: ${detail:-no error text (exit $rc)}" \
    "Check access to the repository" "git ls-remote -- $(show_url "$REPO_URL")"
fi
```

Tests (`test/install_output.bats`, new; loads `install_helper`; `bats_require_minimum_version 1.5.0`). Moved from B8's table: `a failed clone exits 1, says why, leaks nothing`, `optional offers are hidden in CI`, `the printed PATH command works for an awkward prefix`, `the receipt names the version and commit`. New:

| Test name | Assertion |
|---|---|
| `a failed clone shows a Detail row and one recovery command` (F44) | `WORKTREE_HARNESS_REPO=file:///nonexistent`, piped: `$stderr` has `Couldn't clone`, `Detail`, `git:` and `    git ls-remote -- file:///nonexistent`; no line holds `&&`; `$TMPDIR` is empty |
| `a URL credential never reaches the Detail row` (F44, F55) | `user:p@ss@127.0.0.1:9`: the output lacks `p@ss` and `ss@` on every line |
| `a non-writable prefix is refused before any write` (F50) | `[ "$(id -u)" = 0 ] && skip`; `chmod 555 "$D"`; `--prefix "$D/p"`: status 1, `*"isn't writable"*`, `*"Nothing was changed."*`, `[ ! -e "$D/p" ]`; the printed recovery command run with `__WORKTREE_HARNESS_PARSE_ONLY=1` exits 0 (R100) |
| `the recovery command matches how the script started` (F50) | piped: `*"\| sh -s -- --prefix"*`; run as a file: `*"install.sh --prefix"*`, and no line sets the variable before `curl` |
| `a failed copy says the previous install is unchanged` (F50) | `[ "$(id -u)" = 0 ] && skip`; install once; a source copy with `chmod 000` on one lib file: status non-zero, `*"The previous install is unchanged."*`, the old `--version` works |
| `PATH states: on PATH, off PATH, shadowed` (F48, R237) | with `$P/bin` first: bare `worktree-harness` in next steps, no warning. Without it: the `isn't on PATH` warning and absolute paths. With a decoy earlier on PATH: `*"resolves to $DECOY"*` and absolute paths |
| `a trailing-slash PATH entry counts as on PATH` (F48) | `PATH="$P/bin/:$PATH"`: no warning |
| `next steps print one command per line` (F48, R105) | no output line holds `&&`, `` ` `` or a leading `$ ` |
| `next steps follow the current directory` (F48, R237) | in a repo with `.harnessrc`: no `init` line. Outside a repo: `cd <REPO>` comes first |
| `a backslash in the prefix survives under dash` (F48) | `command -v dash \|\| skip`; prefix `a\tb`, `dash install.sh`: the receipt contains the literal path |
| `the guidance variable hides optional steps and keeps the warning` (R238) | variable set, `$P/bin` off PATH: `Next steps` absent, the PATH warning present |
| `fresh, replaced, and unchanged receipts` (F52, R326) | first run: `Installed`, no `Replaced`. Second identical run: `is already installed.`, status 0, share dir inode unchanged. A source with one changed lib file and the same version: `Replaced` and `(different content)`. A prior `WH_VERSION="0.1.0"`: `Replaced` and `0.1.0` |
| `a lost link isn't reported as already installed` (F52) | install; remove the link; re-run: the link is back, output lacks `already installed` |
| `a closed stream doesn't abort the install` (F47, R341) | `sh install.sh >&-`, `sh install.sh 2>&-` and `sh install.sh \| head -n 0`: each exits 0 (first status of the pipe) and `"$P/bin/worktree-harness" --version` works |
| `plain output is ASCII from column 0` (F49, R205) | no pty: output has no `✓`, `→`, `·` (`LC_ALL=C grep -nP '[^\x00-\x7F]'` on the output with an ASCII prefix prints nothing), and `Installed worktree-harness` starts a line |
| `rich rows use the 16-character label column` (F49, R181) | under `script`: `✓ Installed` and a line equal to `  Version         <VER> (commit <C>)`. Skip without `script` |

Size: source ~80 moved + ~130 new, tests ~35 moved + ~145 new = **~390 LOC** (estimated: row-by-row line counts, tests at ~9 lines per case).

### B11 (Round 2b): install.sh `--json` (F53). Owns `install.sh` (fires after U-B10 merges), `test/install_json.bats` (new)

Needs D-R2-15. The default is (a) below, because the repo documents no reason to deviate: `CONTRIBUTING.md` and `docs/DESIGN.md` are silent, and hand encoding satisfies the no-dependency rule. Under (b) this unit is one R422 exception row in `docs/DESIGN.md` and one contract test (~15 LOC).

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R243 R100 R101 | B8-1's parser and help | Add `--json` (R068: also `--json=true\|false`, `--no-json`). Examples: `    sh install.sh --json` replaces `    sh install.sh --prefix <DIR>`, so the list stays at 3 distinct jobs (R091). B8's `every --help example parses` covers it (test below). Zero-argument stdout and exit 0 are unchanged, so `ci.yml:60-61` and README.md:149/:155 stay intact. Document `curl … \| sh -s -- --json`. |
| 2 | R244 R248 R249 R250 R251 R033 | success path | Suppress every `say`, so stderr stays empty. Print one document, 2-space on a TTY and compact otherwise: `{"install":{"path":"<BIN_DIR>/worktree-harness","version":"<v>"\|null},"outcome":"installed"\|"replaced"\|"unchanged","next":[{"command":"worktree-harness doctor","argv":["worktree-harness","doctor"]}]}`. `outcome` is B10-4's state, so `unchanged` is real rather than F53's unreachable value. `next` is required after a mutation and ignores guidance (R249); it uses the absolute path when the bin dir is off PATH. |
| 3 | R309 R312 | PATH warnings | The two B10-3 warnings become `"warnings":[{"reason":"not_on_path"\|"shadowed","message":"…"}]`, or that fact is lost. Both reasons are new, so install.sh keeps a one-line registry naming them (R312; Reference K has no PATH reason). |
| 4 | R253 R255 R113 R010 | `on_exit`, `fail`, `git clone` | `fail` and the EXIT handler write exactly one line on stderr: `{"status":"error","reason":"<r>","message":"…"}`, and nothing on stdout, keeping the exit code. Reasons: `invalid_arguments`, `unknown_option`, `conflict`, `clone_failed`, `internal_error`, matching the shape of A.3-7. Tool stderr goes to a temp file, because raw `mkdir`, `cp`, `chmod`, `ln` or git messages would break R253. `--json` is non-interactive, so C7's prompt fails with `confirmation_required` (R010: `--json` grants no consent). `GIT_TERMINAL_PROMPT=0` applies under `--json` from the start, since `--json` has no prior contract. A signal writes `{"status":"error","reason":"canceled","message":"Canceled.","data":{"remote":"none"}}` and keeps 130, 143 or 129 (R262, R336). |
| 5 | R071 R086 | encoding; `--version` | POSIX sh, no jq, no sourcing `lib/`. Escape `\` and `"` with sed. A prefix holding a control character is refused with `invalid_arguments` rather than emitting invalid JSON. Under D-R2-2 (b), `--version --json` prints `{"version":"<v>"}`. |
| 6 | R252 R454 | `--fields` | F53 doesn't address it, and the rule applies to a command with a result schema. D-R2-15 records the choice; the recommendation is an R422 exception, because the document has two fields and an outcome. |

Tests (`test/install_json.bats`, new; `command -v python3 \|\| skip` where a case parses JSON, and no assertion on key order):

| Test name | Assertion |
|---|---|
| `--json prints one document and nothing on stderr` (R244) | `run --separate-stderr`: `[ -z "$stderr" ]`; python3 parses `$output`; `d["install"]["path"]` equals `$P/bin/worktree-harness` |
| `--json outcome is installed, replaced, unchanged` (R248, R033) | three runs with the same three fixtures as B10's receipt test |
| `--json next names the inspect command` (R249) | `d["next"][0]["argv"][-1] == "doctor"`; the absolute path when `$P/bin` is off PATH |
| `--json carries the PATH warning in the document` (R309) | `$P/bin` off PATH: `d["warnings"][0]["reason"] == "not_on_path"`, `[ -z "$stderr" ]` |
| `--json failure is one line on stderr` (R253) | clone failure, piped: status non-zero, `[ -z "$output" ]`, one stderr line, `*'"reason":"clone_failed"'*` |
| `--json usage error is one line, exit 2` (R253) | `--json --bogus`: status 2, `[ -z "$output" ]`, `*'"reason":"unknown_option"'*` |
| `--json escapes a quote and a backslash in the prefix` (R071) | prefix `a"b\c`: python3 round-trips the path |
| `--json refuses a control character in the prefix` | prefix holding a tab: non-zero, `*'"reason":"invalid_arguments"'*`, nothing written |
| `--json example parses` (R100) | `every --help example parses` now also runs `sh install.sh --json` with `__WORKTREE_HARNESS_PARSE_ONLY=1`: status 0, `[ ! -e "$P" ]`, and the extracted list contains that line, so the new example can't be skipped silently |
| `zero-argument output is unchanged by this unit` (R402) | the receipt and next steps match B10's expectations with no `--json` |

Size: source ~85, tests ~80 = **~165 LOC** (estimated: same method).

### B9 (Round 2): help metadata, help search, drift and presentation tests (after U-B7). Owns `lib/help_meta.sh` (new), `test/help.bats` (new), `test/presentation.bats` (new), `bin/worktree-harness` (help arm only; U-B1 has merged), README.md help row and CHANGELOG `Added` lines (U-B7 has merged)

| # | Rules | Site | Change |
|---|---|---|---|
| 1 | R106 R087 R032 R063 | `lib/help_meta.sh` (new) | One command index (R032): a TSV here-doc read with `while IFS="$(printf '\t')" read -r …` (bash 3.2-safe; no associative arrays). Per canonical command it holds the summary, usage, options (long, short, type, value hint, default, accepted values, repeatable, deprecated), examples, and the result schema (status only, from B3-12). `_wh_help_json <cmd>` (the A.3-4 hook) prints `{"path":"worktree-harness <cmd>","summary":…,"arguments":[…],"options":[…],"examples":[…],"lifecycle":null,"resultSchema":…\|null}` through `wh_json_str`/`wh_json_out`. |
| 2 | R107 | bin `help` arm (B1-9's `_wh_help_ext`) | `worktree-harness help --all --json` prints `{"commands":[…one document per canonical command…]}` from the same records. |
| 3 | R108 | same | `worktree-harness help search <QUERY> [--json]`: case-insensitive fixed-string match (`grep -iF`) over path, summary, option names and examples. Prints up to 10 rows of `worktree-harness <cmd>  <summary>` on stdout; `--json` gives `{"commands":[{"path","summary"}]}`. No match prints `No commands match "<QUERY>".` and exits 0. A missing query is a usage error. Works offline, and the query is never written anywhere. |
| 4 | R087 R063 R109 (critic `unmentionedRules[13]`) | `test/help.bats` drift guards | (a) Every option in each `<cmd> --help` `Options:` section matches the metadata, and vice versa. (b) Every metadata option parses: `__WH_PARSE_ONLY=1 "$WH" <cmd> <opt> [<sample value>]` exits 0. (c) Each completion file (`share/completions/worktree-harness.bash`, `_worktree-harness`, `worktree-harness.fish`) lists exactly the metadata's canonical commands and non-deprecated options: no `create/run/land/prune`, `gc --force`, `-C` or `-V`. Generating the completion files from the metadata is D-R2-9's alternative. |
| 5 | R401 R404 R191 R212 R115 (critic `unmentionedRules[40]`) | `test/presentation.bats` (new) | For `--help`, `status`, `gc` (preview) and `new <BRANCH> --dry-run` in a fixture repo: (a) output is identical at `COLUMNS=40`, `80` and `120` (the CLI never reads the width; this pins it), and no path contains `…`; (b) `FORCE_COLOR=1` output with ANSI stripped (`sed 's/\x1b\[[0-9;]*m//g'`) equals `NO_COLOR=1` output; (c) `--no-color`, and `TERM=dumb` on a pty via `script` (skipped without it), emit no ESC; (d) under `FORCE_COLOR=1`, `status --porcelain`, `status --json` and `new`'s stdout path contain no ESC (R404: JSON and identifiers stay unstyled). |

Tests (`test/help.bats`): `help --all --json lists every command` (seven `"path":` entries; full validation with python3 when present), `status --help --json declares a result schema`, `help search remove finds gc`, `help search with no match exits 0 with the message`, `help search --json shape`, `help search without a query is a usage error`, drift (a)(b)(c), `every metadata example parses` (R100), and the R2 cross-unit `a config error under status --json is one invalid_config line` (`.harnessrc` with `HARNESS_BASE_POLICY=bogus`; status 1, empty stdout, `*'"reason":"invalid_config"'*`).

Size: help_meta.sh ~150, bin ~15, help.bats ~110, presentation.bats ~70, docs ~8 = **~355 LOC** (estimated: metadata at ~12 lines per command × 7, renderer and search from comparable `cmd_status.sh` loops, tests at ~9 lines per case). **R2b:** one extra line in the same "docs" budget: `CONTRIBUTING.md`'s Layout table (:39-48) gains `lib/help_meta.sh`, which the `lib/cmd_*.sh` row doesn't match. U-B8 has merged by then. B9-4's option drift treats `status --human` as absent, per B3-1 R2b.

---

## 4. Wave C: contract-changing fixes (serialized commits; each updates its callers in the same commit)

### C1: exit-code realignment (F3 + F4 + F15 exit part). **DECISION**
- **Change:** set `WH_EXIT_USAGE=2` (`lib/common.sh`); bin:137 becomes `wh_usage_die "" "unknown command: $cmd"`; `lib/cmd_merge.sh:78` `exit 2` becomes `exit 1` (rebase conflict is an operational Conflict, Reference J); `lib/cmd_doctor.sh:27, :68` `return "$issues"` becomes `return $(( issues > 0 ))`. These go in **one commit**, so that 2 means only "usage" from that commit on.
- **Callers:**
  - `test/dispatcher.bats:19-22` is the only exact-code caller (it asserts 64). Rename it to `unknown command exits 2` and assert `-eq 2`.
  - Every other test asserts `-ne 0` or `-eq 0`.
  - `share/shell/{bash,zsh}.sh:17` and `fish.fish:22` pass `launch`'s exit status through without parsing it.
  - No external callers: verifier grep over `~/Development`, claude-infrastructure hooks/skills/commands/tests and `~/.claude/settings.json`.
- **Tests to add in the same commit:**
  - `-eq 2` for: `--bogus-flag`, `-C` with no directory, `gc --prune junk`, `status --json --porcelain`, `new` with no branch.
  - merge.bats `a rebase conflict exits 1`: feat edits README line 1; `$APP` edits the same line and runs `git push -q origin main`. Assert `status -eq 1` and `*"rebase --abort"*`.
  - doctor.bats `doctor exits 1 for two issues`: bogus BASE_POLICY + `GC_IDLE_MIN=soon` gives `-eq 1`.
- **Migration:** CHANGELOG "Changed (breaking): usage errors exit 2 (was 64 for an unknown command, 1 elsewhere); merge rebase conflict exits 1 (was 2); doctor exits 1 when it finds issues (was the issue count)". Ships in 0.3.0.
- **Why a decision is needed:** two verdicts disagree. The F3 verdict and the guide (R337/Reference L) say 2. The F15 verdict preferred keeping 64 (EX_USAGE, today's dispatcher code) because merge used 2. **Recommendation: 2.** C1 moves merge off 2 in the same commit, which removes the F15 objection. Also confirm 0.3.0 as the release vehicle (published via the Homebrew tap).
- **Size:** ~60 LOC (estimated).

### C2: `gc --prune` consent tier (F6). **DECISION**
- **Change in `lib/cmd_gc.sh`:**
  - Add `-y|--yes=assume_yes` to the parser spec.
  - **Pass 1** runs the existing gates and collects candidates, printing `WOULD remove <base> [<br>]` for each.
  - If prune is set and N > 0, print the effects: `Removing a worktree deletes its directory, including ignored files (copied .env files, local databases, build output). Branches and commits are kept.` followed by `Some effects cannot be undone.` (R148).
  - Then `wh_require_consent "Remove $(wh_plural N worktree worktrees)?" "Can't remove worktrees without --yes in non-interactive mode." "worktree-harness gc --prune --yes" "$assume_yes"`.
  - **Pass 2** re-checks the dirty, busy-marker and lsof gates for each candidate right before `git worktree remove`; a candidate that changed prints `KEEP … changed since preview` (R154).
  - Dry-run never prompts (R325). `--force` stays a deprecated alias for `--prune` and **never** implies `--yes` (R153).
- **Callers updated in the same commit:**
  - `test/gc.bats:9, :19, :29, :40, :58` become `gc --prune --yes`.
  - New tests: `gc --prune without --yes fails in non-interactive mode` (`</dev/null`: `status -eq 2`, `*"--yes"*`, dir still exists); `gc --prune --yes removes`; `dry-run with --prune never prompts`.
  - `SKILL.md:39, :43, :54`: agents use `gc --prune --yes` **only after a human approves the preview printed by `gc`** (R263).
  - `README.md:22, :175, :241`; `bin/worktree-harness:38` help line; all three completion files gain `--yes`/`-y`.
  - `docs/demo.cast:16, :36`: recorded on a TTY, so the prompt now appears. Re-record, or leave it with a note.
  - `lib/cmd_new.sh:142` keeps `gc --prune`: it is a human hint and prompts on a TTY.
  - CHANGELOG.
- **Migration options:**
  - **(A) Full R146:** non-interactive runs require `--yes` now.
  - **(B) One-release bridge:** a non-TTY `gc --prune` without `--yes` still prunes, but prints `Warning: gc --prune without --yes in non-interactive mode is deprecated; 0.4.0 will require --yes.` 0.4.0 then applies (A).
  - **Recommendation: (B) then (A).** Do not add an env-var opt-out; the guide does not count env-based consent.
- **Why a decision is needed:**
  1. **Tier.** The F6 verdict calls it destructive (many inferred targets, ignored-file loss). The strong gates and preserved branches argue it is close to "ordinary". The operator decides whether `gc --prune` belongs in R146's destructive tier.
  2. **Agent workflow.** It changes the workflow SKILL.md documents: agents must now obtain human approval before `--yes`.
  3. **Migration.** Choose between (A) and (B).
- **Size:** ~110 LOC (~50 source, ~30 tests, ~30 docs; estimated).
- **R2 additions to C2** (U-C2 ownership gains `lib/common.sh` and `bin/worktree-harness`; U-C1 has merged by then):
  - **R062 R014 R409 R437 — `--non-interactive` global (Reference B).** A built-in in `wh_parse_opts` and in bin's global loop sets `WH_NON_INTERACTIVE=1`. `wh_require_consent` then treats the run as having no TTY: it never prompts and fails `confirmation_required` (exit 2) naming the `--yes` rerun. It lands here, not earlier, because before C2 the CLI has no prompt (R437: never advertise an option before its behaviour exists). B9's metadata, help and completions gain it in the same commit.
  - **R212 R179 (F37):** the pass-1 preview rows use B2-9's labels and full paths. The round-1 text `WOULD remove <base> [<br>]` above becomes `Remove  <path> [<br>]`.
  - **R091 R100 R263:** gc Examples gains `    worktree-harness gc --prune --yes`, with the Notes line `Agents: add --yes only after a person approves the preview.` The B2 parser test covers it.
  - **R403 mode matrix (critic `unmentionedRules[40]`)** in `test/gc.bats`, with the reapable fixture and each case asserting whether a prompt appeared, what each stream holds, and the exit code. TTY cases use `script` (macOS `script -q /dev/null …`, Linux `script -qec "…" /dev/null`) and are skipped when it is unavailable:
    1. TTY, answer `y`: prompt on stderr, worktree removed, status 0.
    2. TTY, answer Enter: `Canceled.`, status 130, worktree kept (R147/R338).
    3. stdin piped (`</dev/null`): no prompt, status 2, `*"--yes"*`.
    4. stdout redirected on a TTY: the prompt still appears (on stderr).
    5. `CI=1` with a TTY: no prompt, status 2.
    6. `--non-interactive` on a TTY: no prompt, status 2.
    7. `--json`: N/A, gc has no `--json` (D-R2-11).
    8. detected agent: N/A, the CLI has no agent detection (measured: `grep -rn CLAUDECODE bin lib share` finds nothing; critic `unmentionedRules[15]`).
  - **R153 R397:** a test `gc --prune --force without --yes still requires consent` (`</dev/null`: status 2, worktree kept).
  - **R2 size:** +~60 LOC (estimated), so C2 ≈ ~170.
- **R2b additions to C2:**
  - **R068:** `--yes=true|false`, `--no-yes`, and `--non-interactive=true|false` parse through A.3-9. `--yes=false` withholds consent, so it takes the same path as no `--yes`. Add one case to the mode matrix: `gc --prune --yes=false </dev/null`: status 2, worktree kept.
  - **R156, R151 (critic `unmentionedRules[18]`):** `gc --prune --yes` removes a set inferred from local state, with no target in argv. R151 allows that because local state fully determines the set; R156 as written doesn't. The pass-1 preview still prints before acting, even with `--yes` (R002). D-R2-18 records the choice.
  - **Version bump:** if D-R2-2 is (b), the release commit also bumps the install.sh version constant. The test in B8 fails otherwise.
  - **R2b size:** +~5 LOC (estimated), so C2 ≈ ~175.

### C3: unknown evidence is not "0", and gc refuses to guess the default branch (F8 breaking part). **DECISION**
- **`lib/config.sh`:**
  - Add `wh_default_branch_source`, which prints `config|remote-head|local|guessed`. "guessed" means the current-branch fallback at :87.
  - `wh_default_branch` never returns the literal `HEAD`: when detached with no main/master/origin-HEAD it returns empty, and callers already handle empty or failure via `wh_die` paths. Have the implementer audit `cmd_new.sh:24, :136`, `cmd_merge.sh:40` and `config.sh:96`.
- **`lib/cmd_gc.sh`** (the only command that removes things): `[ "$(wh_default_branch_source)" = guessed ] && wh_die "Can't detect the default branch, so gc can't tell what is merged. Set HARNESS_DEFAULT_BRANCH in .harnessrc."`.
- **`lib/cmd_status.sh`:** remove the B3 porcelain shim, so a failed rev-list shows `+?/-?` and a failed dirty check appends `?` to the branch. Git refnames cannot contain `?`, so this stays unambiguous. The footer shows `base: <x> (guessed)`.
- **`lib/cmd_doctor.sh:57`:** `default branch: <x> (guessed — set HARNESS_DEFAULT_BRANCH)`. `config.bats:9` still matches because `main` is detected.
- **Callers:** `status --porcelain` is documented as a script interface (cmd_status.sh:6-7, :15), but no parser exists in the repo or `~/.claude` (verifier grep). `docs/demo.cast:20` shows a real `+0/-0` and is unchanged. Repos with no main/master and no origin/HEAD that relied on the guess will now have `gc` refuse.
- **Tests:**
  - `gc refuses when the default branch is only a guess`: repo trunk `develop`, `git remote set-head origin -d`, no main/master; gives `status -eq 1` and `*"HARNESS_DEFAULT_BRANCH"*`.
  - Same fixture with `HARNESS_DEFAULT_BRANCH=develop` gives status 0.
  - `porcelain shows ? when the comparison fails`: `git -C "$APP" branch -m main trunk`, so origin/HEAD still says main but local main is gone; the row contains `+?/-?`.
  - Update the B3 golden test only for that case.
- **Migration:** CHANGELOG "Changed: `status --porcelain` ahead/behind may be `+?/-?` and the branch may end in `?` when git can't compute them (column count and tabs unchanged); `gc` refuses when the default branch can't be detected."
- **Why a decision is needed:** it changes the value set of a documented machine field, and it makes `gc` refuse in repos that work today. **Recommendation: proceed.** Both changes are fail-closed safety fixes with no known caller.
- **Size:** ~90 LOC (estimated).

### C4: `status` output when stdout is not a TTY (F11 parts that R382 treats as contract). No decision needed.
- **Change in `lib/cmd_status.sh`:**
  - `pretty = WH_TTY_OUT=1 (from wh_init_style; no raw [ -t 1 ] in cmd_status.sh, per R408) || --human`.
  - When stdout is not a TTY and no format flag is given: header `KIND\tBRANCH\tDIRTY\tAHEAD\tBEHIND\tPORTS\tPATH`, then one tab-separated row per worktree with no padding or colour (`DIRTY` = `yes|no|?`; `AHEAD`/`BEHIND` = integer, `-` or `?`) (R189/R209).
  - The footer moves to **stderr** in every human mode (R016/R177).
  - `--porcelain` stays byte-identical and `--json` is unchanged.
- **Callers:** none parse piped `status` (verifier grep over the repo and `~/.claude`). config.bats:15, :23 assert config errors that happen before any output.
- **Tests (status.bats):**
  - `piped status is TSV with a header`: first line equals the header with tabs; no line matches two consecutive spaces.
  - `the footer is on stderr only`: `run --separate-stderr`; `$output` lacks `worktree`; `$stderr` has `(1 worktree`.
  - `--human forces the aligned table when piped`.
  - The `--porcelain` golden test is unchanged.
- **Migration:** CHANGELOG "Changed: piped `status` output is now TSV with a header and the footer moved to stderr; scripts should use `--porcelain` or `--json`." Same release as C1. Also update `README.md:240` and `SKILL.md:38` with the "scripts: use --porcelain or --json" note.
- **No decision needed:** no caller exists. It ships as a contract change only because R382 lists non-TTY table headers and column order.
- **Size:** ~70 LOC (estimated).
- **R2 (R403, critic `unmentionedRules[40]`):** add the TTY case through `script`. On a pty, `status` prints the aligned table on stdout and the footer on stderr; `status | cat` inside the same pty prints TSV with the header. Skip without `script`. +~12 LOC (estimated).

### C5: fetch fails closed, explicit origin policy, invalid config rejected (F14 breaking part). **DECISION**
- **`lib/config.sh` `wh_base_ref`:** a failed fetch becomes `wh_die "Couldn't reach $HARNESS_REMOTE ($url): <first stderr line>. Retry, or use the last-known ref with WH_NO_FETCH=1 (or set HARNESS_BASE_POLICY=local)."` (R292, Network class, exit 1).
- **Explicit policy:** `wh_load_config` unsets `HARNESS_BASE_POLICY` before sourcing `.harnessrc`. If the file set it, record `WH_BASE_POLICY_EXPLICIT=1`; then apply the default.
  - With a missing remote: if the policy is explicit, `wh_die`; if it is the default, keep today's warning and local fallback.
  - Update the config.sh:90-94 comment and the cmd_doctor.sh:63-64 message to match.
- **`lib/cmd_init.sh:30`:** the template writes `HARNESS_BASE_POLICY="origin"` explicitly. Comment it out when the repo has no `origin` remote; otherwise a freshly `init`'ed remote-less repo would now fail.
- **Validation:** move the PM and PORTS checks from `wh_config_warnings` into `wh_config_problems`, so `new`, `merge`, `status` and `gc` reject them before any work and doctor counts them as issues. The `cmd_new.sh:115` guard stays as a backstop.
- **Callers:**
  - `share/shell/{bash,zsh}.sh:17` and `fish.fish:22` route every `claude` in a main checkout through `launch`. **Offline, `claude` now exits 1** unless `WH_NO_FETCH=1` is set.
  - `README.md` (config table, WH_NO_FETCH), `SKILL.md` "Base policy" bullet, `docs/THREAT_MODEL.md:32`, `docs/DESIGN.md:133` (fallback wording).
  - `test/helper.bash:24` sets the policy explicitly with a reachable origin, so it is unaffected.
- **Tests:**
  - `an unreachable remote fails new before creating anything`: `remote set-url origin …/missing.git`; `status -eq 1`, `*"Couldn't reach origin"*`, `*"missing.git"*`, `[ ! -d "$WT_HOME/app/feat" ]`.
  - `WH_NO_FETCH=1 works offline`: status 0.
  - `explicit origin policy with no remote fails`; `default policy with no remote still falls back`.
  - `an unknown package manager fails before any worktree`; `a malformed port entry fails`.
  - The B6 test `a failed fetch names the remote and continues` is inverted in this commit.
- **Migration:** CHANGELOG "Changed (breaking): `new`, `launch` and `merge` exit 1 when the fetch fails (set `WH_NO_FETCH=1` to use the last-known ref); an explicit `HARNESS_BASE_POLICY=origin` with no remote fails; unknown `HARNESS_PACKAGE_MANAGER` and malformed `HARNESS_PORTS` are errors."
- **Why a decision is needed:** offline `claude` launches stop working. Options:
  - **(a)** Fail closed for new, launch and merge (R292).
  - **(b)** Fail closed for `merge` only, where landing onto a stale base is the harmful case; new and launch keep the bounded warning from B6.
  - **(c)** Skip the fetch part of C5 and keep only the validation part.
  - **Recommendation: (b) now.** Revisit (a) once `WH_NO_FETCH` is documented in the shell-integration snippet.
- **Size:** ~130 LOC (estimated).

### C6 (Round 2): install.sh stdout holds only the installed path (F29). No decision needed.
- **Change in `install.sh`:**
  - Every progress, source, receipt, next-step and offer line moves to stderr: the B8 rows 2/8/9/11/12 block is wrapped in `{ …; } >&2`, plus the `Cloning…`/`Installing to…` lines.
  - After the link check (B8-5) passes, print exactly one stdout line: `printf '%s\n' "$BIN_DIR/worktree-harness"` (R016/R173/R177). It prints only on exit 0, never on a failure path (R176).
  - The glyph and offer checks switch from `[ -t 1 ]` to `[ -t 2 ]` (R115: per stream).
- **Callers:**
  - `ci.yml:60-61` does not capture stdout and passes unchanged.
  - README.md:149/:155 are interactive, and both streams reach the terminal.
  - The Homebrew tap does not run install.sh; its test uses `--version` only (Header).
  - External scripts that captured the old prose are covered by the CHANGELOG note.
- **Tests (`test/install.bats`):**
  - `stdout is only the installed path`: `run --separate-stderr`, `[ "$output" = "$P/bin/worktree-harness" ]`.
  - `a failed install prints nothing on stdout`: clone failure, `[ -z "$output" ]`.
  - Flip B8's `streams as of Wave B` test.
- **Migration:** CHANGELOG "Changed: install.sh prints only the installed command path on stdout; progress, receipt and next steps moved to stderr." Ships in 0.3.0.
- **No decision needed:** no in-repo caller reads install.sh's stdout (measured: `git grep -n install.sh`). It is a contract change only because R382 names output streams.
- **Size:** ~40 LOC (estimated).
- **R2b additions to C6 (F47):**
  - **Stdout gate.** "Exactly one stdout line" above holds only outside an interactive TTY. R173 prints the identifier when stdout isn't a TTY or the run is non-interactive, and guidelines.md:549 adds "On an interactive TTY the receipt already shows it". So: `if [ ! -t 0 ] || [ ! -t 1 ] || [ ! -t 2 ] || [ -n "${CI:-}" ]; then ( printf '%s\n' "$BIN_DIR/worktree-harness" ) 2>/dev/null || :; fi`, then `exit 0`. `curl | sh` has a non-TTY stdin, so it still prints the path.
  - **`say` moves to stderr:** `say() { ( printf '%s\n' "$*" ) >&2 2>/dev/null || :; }`. The verifier's model captured the bare path, and `| head -1`, closed stdout, closed stderr and both closed all exited 0 under `/bin/sh` and `/bin/dash` (measured in `/tmp/cli-bp/model-install-streams-run.sh`; a model, not install.sh). B10-5 already landed the closed-stream guard.
  - **F48's overlap.** F48's verifier keeps :26, :31 and :40 on stdout while F47's moves everything but the path. F47 wins (Section 5.1), because this item is where the stream contract and its migration note live.
  - **CI:** the install job asserts the contract: `p=$(WORKTREE_HARNESS_PREFIX="$RUNNER_TEMP/prefix" sh ./install.sh)`, then `test "$p" = "$RUNNER_TEMP/prefix/bin/worktree-harness"`. Keep `:61`. Don't add F47's `2>/dev/null`, so errors stay in the job log. U-C3 therefore also owns `ci.yml:60`.
  - **Compatibility switch:** R388's `<PREFIX>_COMPAT_*` is optional and no in-repo parser needs it, so it isn't planned.
  - **Caller correction:** the Homebrew tap doesn't run install.sh, but its test does more than `--version` (Header, round 2b). Neither is affected here.
  - **Tests (`test/install_output.bats`):** `stdout is a bare path when captured` (`p=$(sh install.sh </dev/null)`); `an interactive TTY gets the receipt and no bare path line` (under `script`; skip without it); `CI=1 on a TTY prints the bare path` (under `script`); `closed streams still install and exit 0` (B10's test, with the stream flipped). R403 for install.sh: interactive TTY, stdout redirected, stdin piped and CI on a TTY are covered by these tests and the two round-2 tests above; `--json` by B11; `--non-interactive` by C7; a detected agent is N/A, since install.sh has no agent detection.
  - **R2b size:** +~30 LOC (estimated), so C6 ≈ ~70.

### C7 (Round 2): install.sh replaces only what it installed; `--force`; receipt outcomes (F26). **DECISION D-R2-4**
- **Change in `install.sh`, before the swap (per F26's refinedFix):**
  - **Ownership of `$SHARE_DIR`.** The installer owns it when it is absent, when it holds the marker `.installed-by-install.sh` (written into the stage, with `WH_VERSION` and the commit), or when it is a pre-marker install: a real directory (not a symlink) holding `bin/worktree-harness` and `lib/compat.sh`. The pre-marker case keeps every existing install upgradable.
  - **Ownership of `$BIN_DIR/worktree-harness`.** The installer owns it when it is absent or is a symlink to `$SHARE_DIR/bin/worktree-harness`.
  - **Refusal.** A path the installer doesn't own, or a `$SHARE_DIR` that is itself a symlink (a typical package-manager link), is refused with `Can't install to <path>. It exists and wasn't created by install.sh.` (Conflict, `file_exists`, exit 1). Recovery: `Replace it anyway:` / `    sh install.sh --force` (for `curl \| sh`: `… \| sh -s -- --force`), then `If Homebrew manages it, upgrade it there instead:` / `    brew upgrade worktree-harness` (R371: never overwrite a package-manager install another way).
  - **`--force`** (R440 spelling, no short form; R153) overrides only these two named targets, and its receipt shows a `Replaced` row. F26's `WORKTREE_HARNESS_FORCE=1` env alternative is dropped (R009: one option per input; `sh -s -- --force` already covers `curl | sh`).
  - **Receipt outcomes (R326/R033):**
    - `✓ Installed worktree-harness <VER>` for a fresh install.
    - `✓ Replaced worktree-harness <OLD> with <NEW>` for an upgrade or reinstall; `<OLD>` comes from the marker or the old `lib/common.sh`.
    - `worktree-harness <VER> is already installed.` (exit 0, no swap) when the version and commit both match.
- **Callers:**
  - `ci.yml:60` installs into an empty prefix: the fresh path, unchanged.
  - README.md:158 already declares both paths installer-owned.
  - Users who pointed the prefix at a Homebrew prefix are now refused. That is intended.
- **Tests (`test/install.bats`):**
  - `refuses a foreign worktree-harness in BIN_DIR`: a regular file there; status 1, file unchanged.
  - `--force replaces it and says Replaced`.
  - `a pre-marker install upgrades without --force`.
  - `the same version twice says already installed`: status 0, no swap (the `$SHARE_DIR` inode is unchanged).
  - `a symlinked SHARE_DIR is refused`.
- **Migration:** CHANGELOG "Changed (breaking): install.sh refuses to overwrite files it didn't create; pass --force to replace them."
- **Why a decision is needed (D-R2-4):**
  - **(a)** Ownership refusal plus `--force`, as above. It breaks only installs over foreign paths. **Recommended.**
  - **(b)** Keep today's silent replacement and add only the Installed/Replaced/already-installed receipts (compatible).
  - **Sub-decision (R146 tier) for replacing the installer's own tree:**
    - *ordinary*: no prompt, as today. **Recommended:** `curl | sh` cannot answer a prompt, and a reinstall restores the tree.
    - *destructive*: require `--yes` when `$SHARE_DIR` exists. This breaks the documented upgrade flow (README.md:149).
- **Size:** ~110 LOC (estimated).
- **R2b corrections to C7 (F42; supersede the rows above where they differ).** Contract: breaking only for the foreign-target branch. A first install, an own rerun, and an own share dir with a missing link all proceed with no prompt (R158), so `ci.yml:60` and README.md:149/:155 are unaffected. Severity is medium per the verifier: the target is always the namespaced `…/share/worktree-harness`, and under a brew prefix only the `:36` link is at risk, never a share dir. All checks run in a preflight before the clone and before any write.
  - **Share dir: judged on its own.** Own when absent, an empty real directory, or a real directory (not a symlink) whose top-level entries are only `bin`, `lib`, `share` and C7's marker, and which holds `bin/worktree-harness` and `lib/common.sh`. The exact top-level match matters, because a git checkout also holds those files; its `.git`, `README.md` or `install.sh` makes it foreign. Tags `v0.1.0` and `v0.2.0` both hold the signature files (measured: `git ls-tree -r`), and their install layout copies only `bin lib share`. This replaces the pre-marker signature above.
  - **Bin link: judged on its own.** Own when absent, or a symlink whose raw `readlink` text equals `$SHARE_DIR/bin/worktree-harness`. Compare strings rather than using `cd -P`, so a dangling link left by a partial uninstall counts as own and a Homebrew `../Cellar` link doesn't. A real directory at the link path stays a refusal even with `--force`, because the rename would nest inside it.
  - **Source overlap.** B8-3's refusal has no override: `--force` doesn't reach it.
  - **Refusal copy.** `Can't install to <path>. It isn't a worktree-harness install.`, each path that would be replaced on its own line, the rerun command, exit 1, nothing written (Conflict, `file_exists`). This replaces the row's `It exists and wasn't created by install.sh.` Under `--json`, one error line. `--yes` alone doesn't override it (R151, R153).
  - **`--force` is not consent for an inferred target (R146, R153, R156, R350).** The row's `sh install.sh --force` recovery is wrong for that reason. `--force` prints the per-path preview ending `This cannot be undone.` (R148), then:
    1. `--yes` with an explicit `--prefix`: proceed, and the receipt shows a `Replaced` row.
    2. `--yes` without `--prefix` on a TTY: the prompt still runs and says the target isn't named (R152). Non-interactive: exit 2, `Can't replace <path> without --prefix in non-interactive mode.`
    3. No `--yes`, stdin and stderr are TTYs, `CI` unset: `? Replace <n> paths? (y/N)`, default No (R147). Enter exits 130 with `Canceled.` (R338).
    4. No `--yes`, non-interactive: exit 2, `Can't replace <path> without --yes in non-interactive mode.`, reason `confirmation_required`. `curl | sh` always lands here, because `[ -t 0 ]` is false, so the script's stdin is never read.
  - **Printed rerun.** `curl -fsSL <url> | sh -s -- --prefix <PREFIX> --force --yes`, or `sh install.sh --prefix <PREFIX> --force --yes` from a checkout, with the real prefix quoted by `shq` (R103). The row's `brew upgrade` line stays second (R280: at most two options).
  - **`--non-interactive`** (R062, R437) lands here, because this commit adds install.sh's first prompt. **R068:** `--force=true|false`, `--no-force` and the same for `--yes` parse.
  - **Example.** Help gains `    sh install.sh --prefix <DIR> --force --yes` (R091: risky use), and README.md:158 documents `--force`, `--yes` and `--prefix` in this commit (`CONTRIBUTING.md:33`).
  - **Recorded conflict.** R156 read literally demands a target in argv on every non-interactive run, which would break `ci.yml:60` (env only) and README.md:149 (default). Caller compatibility wins, so the argv requirement applies only to the destructive branch (R422 entry in B7).
  - **Dependency.** This design needs D-R2-3 (a). Under (b) there is no `--prefix`, so R156 can't be met on the destructive branch and that becomes a recorded exception.
  - **Receipts.** The `Receipt outcomes` bullet above is done by B10-4, so D-R2-4 (b) now means "no refusal". The marker is still written here.
  - **R371** is only a weak citation here: there is no upgrade command, so just its "don't overwrite a package-manager install" clause applies, and only under an explicit prefix override.
  - **Tests (`test/install.bats`).** Amend `--force replaces it and says Replaced` to pass `--prefix "$P" --force --yes`. Remove `the same version twice says already installed` here (B10 has it). Add: `--yes alone doesn't override a refusal` (status 1, file unchanged); `--force without --yes fails in non-interactive mode` (`</dev/null`, status 2, `*"--yes"*`, unchanged); `--force --yes without --prefix fails in non-interactive mode` (env-only prefix, status 2, `*"--prefix"*`); `a checkout copy without .git at SHARE_DIR is foreign` (a copy holding `README.md`: status 1); `a Homebrew-style relative link is foreign` (`ln -s ../Cellar/x "$P/bin/worktree-harness"`: status 1, link unchanged); `a dangling own link counts as own` (status 0, no prompt); `an own share dir with a missing link needs no --force` (status 0); `a real directory at the link path is refused even with --force` (status 1); `a first install and an own rerun never prompt` (`</dev/null`: status 0 both); TTY cases under `script`, skipped without it: answer `y` replaces, Enter gives 130 and no change (R403); `the printed rerun parses` (extract it from the refusal, run it with `__WORKTREE_HARNESS_PARSE_ONLY=1`: status 0, nothing changed, R100); `every --help example parses` now also runs the `--force --yes` example, and the extracted list must contain it (R100).
  - **R2b size:** ~+90, minus ~25 for the receipt move, so C7 ≈ ~175 (estimated).

### C8 (Round 2b): install.sh exit codes and prompt default (F44, F46 contract parts). **DECISION D-R2-12 for the `~` rule only**
- **Change in `install.sh`:**
  - **Failed clone.** B10-1's `fail "$rc"` becomes `fail 1`, so a failed clone exits 1, not git's 128 (R337). `[ "$rc" -le 128 ] || exit "$rc"` stays, because Reference L reserves 128+n for signals. The clone is an internal step with discarded streams, so Reference L's child-code row doesn't excuse 128.
  - **Typed credentials.** `GIT_TERMINAL_PROMPT="${GIT_TERMINAL_PROMPT:-0}" git …` (R014), so a private or mistyped URL fails rather than prompting on `/dev/tty` in a run whose stdin is the script. The `:-` keeps `GIT_TERMINAL_PROMPT=1` working. Credential helpers, `GIT_ASKPASS` and SSH keys are unaffected.
  - **Dash-leading URL.** `case "$REPO_URL" in -*) …` gives `WORKTREE_HARNESS_REPO must be a repository URL, got: <value shown>.`, exit 2 (today 128 or 129), before any write.
  - **Quoted `~` (if D-R2-12 is (a)).** `case "$PREFIX" in "~"*) …` gives `WORKTREE_HARNESS_PREFIX starts with ~ and wasn't expanded: <value>. Use $HOME or an absolute path.`, exit 2, before any write. Today this exits 0 with a literal `~` directory and a dead link, so the exit 0 was a false success. It's a contract change only because guidelines.md:1213 lists exit codes.
- **Callers:** none parse these. `ci.yml:60` takes the checkout path and never reaches the clone; no test or doc mentions 128; `WORKTREE_HARNESS_REPO` appears only at install.sh:12 at `b586f99` (measured: `grep -rnI`). Not checkable from this repo: public `curl | sh` users and the private-URL case.
- **Tests:** flip `a failed clone exits 1, says why, leaks nothing` and the credentials test from `-ne 0` to `-eq 1`. Add: `a prompt is never attempted` (`GIT_ASKPASS` unset with a local URL that demands auth isn't portable, so assert with a `git` shim that records `GIT_TERMINAL_PROMPT=0` in its environment); `GIT_TERMINAL_PROMPT=1 is honoured` (same shim); `a dash-leading repo URL is a usage error` (`--bogus`: status 2, nothing written); `a quoted ~ prefix is refused` (D-R2-12 (a): `WORKTREE_HARNESS_PREFIX='~/x'`: status 2, `[ ! -e './~' ]`).
- **Migration:** CHANGELOG "Changed (breaking): a failed clone exits 1 (was git's 128) and no longer prompts for credentials (set `GIT_TERMINAL_PROMPT=1` to allow it); a dash-leading `WORKTREE_HARNESS_REPO` and a quoted `~` prefix exit 2." Ships in 0.3.0.
- **Size:** ~55 LOC (estimated).

---

## 5. Dropped (one line each)

- **Config strings through `eval`/word splitting (R360/R071/R355):** refuted. The eval'd values are trusted `.harnessrc` shell, as documented in docs/THREAT_MODEL.md and SECURITY.md, and `launch -- <cmd>` already passes argv as an array. The only real residual is unguarded globbing at `cmd_launch.sh:52`, handled as optional item B4-10.
- Sub-claims refuted inside kept findings (do **not** implement):
  - **F4:** "256 issues wraps to 0" is impossible; doctor tops out at 3.
  - **F13:** "no 130 exit" is wrong; untrapped SIGINT already yields 130. Only the recovery message was missing.
  - **F5:** the fix location "repo check inside `wh_load_config`" would break `launch` outside a repo; it is replaced by `wh_require_repo`.
  - **F5:** R339 does not apply (every path already exits non-zero).
  - **F12:** `cmd_merge.sh:102` (`git fetch .`) does not leak to stdout.
  - **F12:** R273 does not apply to internal git plumbing.
  - **F17:** "git worktree add failed gives no cause" is wrong; git's stderr already passes through (`>&2`). Only the headline changes.
  - **F17:** R099 has no applicable site.
  - **F18:** locking `info/exclude` is dropped; it is a single guarded O_APPEND line and a race only duplicates a harmless ignore line.
  - **F18:** `HARNESS_COPY` `..`/absolute-path validation (R352) is dropped, because `.harnessrc` is trusted code.
  - **F18:** "only `.env*` gets chmod" is a documented design (README.md:95).
  - **F14:** a non-numeric port is not handled "quietly"; it already warns. It is promoted to an error in C5 only.
  - **F11:** `--porcelain` lacking a header is git porcelain convention and is kept.
  - **F15:** "use exit 64" is overridden by R337 (see C1).
  - **F15:** `--x=value` beyond `-C` is moot; no other option takes a value, though the shared parser supports it.
  - **F6:** R263's JSON envelope (`userActionRequired`, `data.effects`) is not applicable; this CLI has no JSON consent path. Only the human-mode part applies (confirmation_required, exit 2).
- **Vercel-specific:** none of the kept or dropped findings are Vercel-specific (every verdict has `vercelSpecific:false`).
- **Round 2: sub-claims refuted or narrowed inside F22–F36** (do **not** implement):
  - **F22, F27, F28, F30, F31, F34:** the finders' "breaking" labels are replaced by the verifiers' "compatible". No caller passes argv to install.sh, parses its text or depends on exit 128. **R2b:** superseded for F28's exit code and prompt default, which F44's verifier rates breaking; those parts move to C8. No caller depends on them either, but they are contract under R382.
  - **F23:** a bare `[ -f "$0" ]` is not enough, because a file named `sh` in the cwd would pass it. The basename check is required. The optional `--from`/`WORKTREE_HARNESS_SRC` is not planned.
  - **F25 and F28:** the `trap 'rm -rf "${TMP:?}"' EXIT` they propose would fail under `set -u` on the checkout path (CI's path). A guarded `cleanup()` is used instead.
  - **F26:** the `WORKTREE_HARNESS_FORCE=1` env alternative is dropped (R009).
  - **F27:** rejecting a relative prefix with exit 2 is not planned. The prefix is made absolute instead.
  - **F30:** R099 does not apply, since no short options are printed.
  - **F31:** R241 is a weak fit (these are offers, not `Tip:` lines). It is still met through the guidance variable.
  - **F32:** R371 does not apply (the CLI has no upgrade command). The receipt is on stdout until C6, not on stderr as the finding says. The install marker belongs to C7.
  - **F33:** the rename to `__WORKTREE_HARNESS_REPO` is dropped (R079: legacy names keep their names).
  - **F34:** the finding's "check the stderr TTY" checks the wrong stream until C6.
  - **F35:** R002/R148 apply only to an optional `--uninstall`, which is not planned. The verdict's `uninstall:   … && …` line is replaced (R183/R105).
  - **F36:** assertions for behaviour that does not exist yet land with the change that adds it, in the same unit. They are not written first.
- **Round 2: critic2 entries verified and needing no plan change** (static reading at `b586f99`):
  - `unmentionedRules[4]` (R033/R035 verb): `gc` mirrors `git worktree remove`. C2's preview already states that the directory and its ignored files are deleted (R148), and B2-9 makes the preview and receipt use one verb (Remove/Removed).
  - `[5]`, `[6]`: N/A. The CLI is flat (bin:82-137, no groups) and never resolves `worktree-harness-<x>` extensions.
  - `[9]`: `wh_set_defaults` (config.sh:19-33) overwrites `HARNESS_*` from the environment. Those are `.harnessrc` settings, never documented as env vars, so this is not counted. The Wave B help rule forbids presenting them as env vars.
  - `[15]` (R112/R117/R119): N/A, since there is no agent detection (`grep -rn CLAUDECODE bin lib share`: no hits).
  - `[32]` (R326): `merge` on an already-landed branch prints `<def> already contains <branch> (<sha>) — nothing to do.` and exits 0 (cmd_merge.sh:53-55). `init` over an existing file is a Conflict, exit 1 (cmd_init.sh:15), which Reference J allows. Only gc (B2-11) and install (C7) needed fixes.
  - `[37]`: N/A (no update notifier or telemetry).
  - `[39]` (R383–R385): followed. `-C`/`-V` handling under D-R2-1 follows R385.
  - `[42]` (R432): `status` runs no fetch (cmd_status.sh:27-32 calls only `wh_load_config`, `wh_repo_root` and `wh_default_branch`; `wh_base_ref` is never called), so it is satisfied. `--json` comes in B3.
  - `[43]`:
    - R471/R476: `grep -rniE '\b(the|a|this) resource\b|login|logout|rollback|signup' bin lib share` finds nothing.
    - R477: the product name is the lowercase command name by design.
    - R472: handled by F32.
    - R473: handled by B4-11.
  - `planConflicts[3]`: names this plan as the consistent case (R439/R337/R438 adopted as general practice). This round drops no rule as Vercel-specific and introduces no `--format`, `--confirm`, `-f`, money hint or exit code outside Reference L. `planConflicts[0,1,2,4,5]` and the other `missedFindings`/`uncoveredClis` entries concern other repos.
- **Round 2b: sub-claims refuted or narrowed inside F41–F58** (do **not** implement):
  - **F41:** the finder's "breaking" becomes compatible. Its unconditional "`--version` prints the version" can't work under `curl | sh`, because `WH_VERSION` lives only at `lib/common.sh:12` (D-R2-2). High severity is generous on damage, since the `rm` only hits the tool's own directory, but a help option doing destructive work stays a MUST violation.
  - **F42:** the literal "otherwise refuse" would reject first installs and break `ci.yml:60`. A combined share-and-link test would refuse an own share dir with a missing link. The Homebrew risk is the `:36` link only. R371 is a weak citation.
  - **F44:** "hangs indefinitely" isn't proven: connect-phase limits weren't read or measured. R019 is a weak fit, and R313 is the operative rule. R292's proxy half isn't violated, because nothing disables proxies. A prompt wasn't reproduced. Git's last line isn't the Detail line, and the `install:` prefix isn't used (R276).
  - **F46:** "can inject a git option" has no demonstrated impact. The newline rejection is dropped, because it would break a working value. Empty values are documented rather than changed (D-R2-7 (a)). R071 fits weakly. The finder's "breaking" holds only for the C8 rejections.
  - **F47:** R176 isn't violated today; it constrains the fix. `./install.sh | head -1` from a checkout still installs; the mid-install death needs the clone path. An unconditional bare path would duplicate the receipt on a TTY.
  - **F48:** "fails as printed" holds only if the user skips :43. README.md:187 and :197 aren't yet a complete replacement for the offers. R099 still has no site.
  - **F49:** the finder's "breaking" becomes compatible, since no caller parses this copy. `✓` at :40 complies with R182. R221 is the weakest citation.
  - **F50:** a `|| err "… isn't writable"` wrapper would guess the cause. R286's role formula has no server role here, so only the writable-prefix route applies.
  - **F51:** there is no swap today, and the temp leak exists only on the clone path. B8-18's handlers are tested on stand-ins, not install.sh.
  - **F52:** "can't tell what they got" is overstated, since `--version` and `doctor` show it. R153 and R180 aren't violated, and R371 doesn't apply, so signed checksums aren't planned. `main` carries the same code as `v0.2.0` today (measured: `git diff --stat v0.2.0 HEAD -- bin lib share install.sh` prints nothing).
  - **F53:** only R243 fires today; R244, R248 and R253 constrain the fix. "Must scrape prose" is overstated, because `ci.yml:61` scrapes nothing. Its `"unchanged"` value is only real after B10-4. Its Option B "bare stdout path" doesn't exist until C6.
  - **F54:** R009 doesn't apply. `HARNESS_*` are `.harnessrc` keys overwritten by `wh_set_defaults` (`lib/config.sh:19-34`), not a second name for one input. The rename to `__WORKTREE_HARNESS_REPO` is dropped, because a mirror override is a real public use. R079's naming clause protects both legacy names.
  - **F55:** the finder's sed, like round 2's, leaks part of a password containing `@`.
  - **F56:** "curl's failure goes unseen" is too strong: `-S` prints it, and only the status is lost. The byte window is narrow (200 of 2,106 bytes, measured by the verifier with awk). R015 is a loose fit.
  - **F57:** the shellcheck half has no checklist basis; it is repo hygiene that's green on day one. By static reading, five of its seven test cases fail against today's installer, so each lands with the change that creates the behaviour (same rule as F36).
  - **F58:** R008 is mis-cited (D-R2-19). The verifier's correction to the finder's wording, that a failure leaves the temp dir behind, is true only until B8-18 lands; B7's text describes the code after it.
- **Round 2b: critic2 entries round 2 didn't list, verified against `b586f99`** (no plan change unless named):
  - `unmentionedRules[1]` (R020, R165, R293, R300, R315, R317): N/A. The CLI retries nothing; `git fetch` and `git clone` run once.
  - `[14]` (R110): N/A, no lifecycle labels. `[35]` (R345, R346): N/A, no paging. `[36]` (R365): N/A, no local servers. `[41]` (R419–R421): process rules.
  - `[18]` (R149, R156, R157, R158): `grep -inE 'can undo|reversible|selected|Are you sure|Continue\?' bin lib share install.sh` finds nothing (measured). The plan's prompts name counts (`Remove N worktrees?`, `Replace <n> paths?`). R158 is met: own reruns don't prompt. **R156 isn't obviously met by C2's `gc --prune --yes`:** D-R2-18.
  - `[23]` (R202, R208, R211): no `38;5;`, `38;2;` or `48;` codes (measured with grep); no URLs are styled; B9-5 pins width behaviour.
  - `[25]` (R214–R218): N/A except `modified <N min ago` (`cmd_gc.sh:68`), which is a spaced duration in a sentence and allowed by R214.
  - `[26]` (R221–R234): no `sorry`, `you entered`, `invalid input` or curly quotes in `bin lib share install.sh` (measured with grep). `master` appears only as a literal branch name (`lib/config.sh:84`, `lib/cmd_merge.sh:42`, `lib/cmd_new.sh:26`), which R234 keeps. Install copy under F49 covers R221.
  - `[29]` (R265–R272): N/A, no streaming output. `[30]` (R281–R305 API mapping): N/A, no API client; R282 applies to `fail` (B10-2).
  - `[0]` is the critic's method note. `[2, 3, 16, 17, 19, 20]` name other repos (agent-secrets, doc_classifier, agentsync); this CLI has no secrets, menus, spending or login.
  - `[33]` (R327–R333): `wh_base_ref` prints a step before fetching (`lib/config.sh:103`), and no `--wait` or follow mode exists. `[34]` (R340, R342): no offers to decline in the CLI, and it has no EXIT trap. install.sh gets R342 in B8-18. `[38]` (R374): N/A, no API enums.
  - Re-read this round with no change: `missedFindings[6]` (`cmd_gc.sh:52, 80, 85, 94`), `[7]` (`bin/worktree-harness:68, 72`), `[8]` (`cmd_gc.sh:53, 57-71, 93`), `[11]`, `uncoveredClis[5]`.
  - **Plan scan for what `planConflicts` flags** (measured: `grep -nE -- '--format|--confirm|<CENTS>|<N>|<COUNT>|<MS>|--overwrite|--output json|-F\b'` on this plan before this round's edits): only `declare -F` and git's own `log --format`. No banned spelling or hint; no rule dropped as Vercel-specific (`vercel` appears only in lines saying so). This repo has no `package.json`, so `planConflicts[2]`'s `node_modules` class of error can't occur here. Rules the plan leaned on but contradicted are fixed: R438 (B3-1), R309 (A.3-10), R068 (A.3-9), R113 (A.3-8, B8-9), R181 (B8-11), R173 (A.3-11, C6), R086 (D-R2-2, D-R2-17).

---

### 5.1 Overridden recommendations: cross-finding conflicts resolved in this plan

| Conflict | Resolution |
|---|---|
| Usage exit code: 2 (F3, guide) vs 64 (F15) | 2, in C1, together with merge conflict 2 → 1 and doctor's count → 0/1 in the same commit |
| `status --human`: deprecate (F16) vs force the aligned table (F11) | Keep and document it as "force the aligned table" (B3); no warning |
| `gc --prune --dry-run`: reject as a conflict (F15) vs dry-run wins (F1) | Dry-run wins with an info line (R325: dry-run never fails or prompts; conservative) |
| F2/F4/F7/F11/F13 labelled "breaking" by the finders vs "compatible" by the verifiers | Follow the verifiers. F4 still goes to C1 because of the exit-2 coupling. F11's piped-format and footer-stream parts go to C4 because R382 names non-TTY headers and streams as contract. |
| Repo check placement (F5) | `wh_require_repo` in common.sh (Wave A), called per command; never in `wh_load_config` |
| (R2) A.1 `See: worktree-harness <cmd> --help` on one line vs R105/R084 and the guide's usage-error exemplar | Headline, blank line, `See all options:`, then the command indented on its own line. A.1 is edited, and the A.2/B1/B4 assertions are updated |
| (R2) A.1 rich `wh_step "→"` (repo convention, lib/common.sh:26) vs R182 (blank progress gutter; F34 verdict) | Follow R182 in lib/common.sh and install.sh. The convention is style, not a repo rule (no CLAUDE.md; CONTRIBUTING.md is silent). D-R2-6 records keeping `→` |
| (R2) A.1 makes `-C` a built-in of every command vs R466 (critic `missedFindings[7]`) | `--cwd <DIR>` is canonical everywhere. `-C` is kept for caller compatibility (`test/gc.bats`, README.md:245, bash completion) per D-R2-1 and never advertised |
| (R2) B1-2 "For command options, run: …" vs R096 (no hint to run help) | Line dropped |
| (R2) B1-2 `ENVIRONMENT` section vs R087's section list | Each variable is documented beside the global option it mirrors and in the Notes of the commands it affects |
| (R2) Wave B keep-substring `"unknown global flag"`/`"unknown command"` vs R060 and the Reference J headlines | New headlines; U-B1 updates `dispatcher.bats:22,:28` in the same commit (R383 human copy) |
| (R2) B2-6 removed paths on stdout even when gc exits 1 vs R176 | Stdout only on exit 0 (B2-10); partial runs list the removed paths on stderr |
| (R2) F25/F28 `${TMP:?}` EXIT trap vs `set -u` on the checkout path (F25 verdict) | One guarded `cleanup()` (B8-4) |
| (R2) F35 `uninstall:   rm -rf … && rm -f …` vs R105/R183 | One `rm -rf --` command on its own line after a benefit sentence (B8-12) |
| (R2) F31 `WORKTREE_HARNESS_GUIDANCE_DISABLED` vs the CLI's `WH_` env prefix (R009: one variable for one concept) | One variable read by both the CLI and install.sh, named per D-R2-5 |
| (R2) Round 1 "docs in B7" vs `CONTRIBUTING.md:33-34`/PR template :11 (docs in the PR that changes behaviour) | The repo rule wins: Wave B lands on `cli-bp/wh-wave-b` and reaches `main` in one PR with its docs (Landing flow item 7; D-R2-10) |
| (R2) F36 "write every install test now" vs current behaviour | Each assertion lands with the change that creates the behaviour (B8 test table) |
| (R2b) B8-6's exit 1 and `GIT_TERMINAL_PROMPT=0` vs Wave B's no-exit-change rule and F44's "breaking" verdict | Both move to C8. Wave B keeps git's code and keeps prompts; the copy lands in B10-1 |
| (R2b) F47 moves everything but the path to stderr vs F48 keeps :26, :31, :40 on stdout | F47 wins, in C6, which carries the stream contract and migration note |
| (R2b) F44's `install:` prefix and `Check access with: …` inline vs R276, R205 and R280 | The shared `fail` layout: `✗`/`Error:` headline, Detail row, recovery instruction, indented command |
| (R2b) F50's "previous install was already removed" vs B8-4's stage | Messages follow the stage: before the swap the previous install is unchanged |
| (R2b) F52 keeps the `✓ installed:` literal vs F49's `✓ Installed …` | F49 and B8-11 win; no caller parses it and the verifier rates that copy compatible |
| (R2b) F51's "`Stopped waiting.` in the mutating phase" vs B8-4's restore | `Canceled.` when the restore put the old tree back; `Stopped waiting.` only after the swap, when the new tree is in place |
| (R2b) C7's `--force` alone vs R146, R153, R156 (F42) | `--force` plus `--yes` plus an explicit `--prefix` for an inferred target |
| (R2b) R156 literal, target in argv on every non-interactive run, vs `ci.yml:60` and README.md:149 | Caller compatibility wins: the argv requirement applies only to the destructive branch. R422 entry recorded in B7 |
| (R2b) R086 "prints only the version" vs `worktree-harness <v>` at bin:72, `Formula/worktree-harness.rb:36`, `test/dispatcher.bats:5-7` | Caller compatibility wins for the CLI: bytes unchanged, D-R2-17. install.sh has no prior contract, so it prints only the version under D-R2-2 (b) |
| (R2b) R438 "the only format selector" vs `status --porcelain` (documented) and `--human` (undocumented today) | `--porcelain` keeps its documented contract; `--human` stays accepted and is never advertised, reversing round 1's "document it". R422 entry in B7, D-R2-16 |
| (R2b) A.3-7's no-op `wh_warn` in JSON mode vs R309 | Warnings go in the document (A.3-10) |
| (R2b) A.1's `Option <x> doesn't take a value.` vs R068 | `=true`, `=false` and `--no-` parse (A.3-9); any other value is the usage error |
| (R2b) R313's total limit vs no portable `timeout` on stock macOS and `CONTRIBUTING.md:8` (no new dependency) | The repo rule wins: low-speed limits cover HTTP stalls, and the gap is a recorded R422 exception, not a dropped rule |
| (R2b) R307's `!` vs `⚠` at `lib/common.sh:28` (F48's recorded conflict) | Dissolves: A.1 already moves `wh_warn` to `!`, and install.sh uses the same glyph |
| (R2b) F45's `Source:` label vs R183 | A progress sentence, `Installing from <URL shown>…`, per B8-2 |
| (R2b) F48's `<PROJECT_DIR>` vs R102 | `<REPO>`, a noun placeholder with no extra label |
| (R2b) F58's text "leaves it behind" (verifier) vs B8-18 | B7 describes the code after B8-18 |

---

## 6. Implementation sizing

All LOC figures are **estimated** by counting the lines each listed change adds or edits, using the cited code read for this plan. Tests are counted at ~8–15 lines per bats case, the size of the existing cases in `test/*.bats`.

| Wave | LOC (est.) |
|---|---|
| A | ~300 |
| B | ~1,130 (B1 150, B2 160, B3 145, B4 275, B5 160, B6 170, B7 70) |
| C | ~460 (C1 60, C2 110, C3 90, C4 70, C5 130) |
| **Total** | **~1,890** |

### Implementer units (each under 500 LOC; file ownership is exclusive while the unit runs)

| Unit | Wave | Owns (exclusive) | Items | LOC (est.) | Depends on |
|---|---|---|---|---|---|
| U-A | A | `lib/common.sh`, `test/common.bats` (new), `test/helper.bash`, `bin/worktree-harness` (2-line hook after :79 only) | A.1, A.2 | ~300 | none |
| U-B1 | B | `bin/worktree-harness`, `test/dispatcher.bats` | B1 1–6 | ~150 | U-A; merge after U-B3 |
| U-B2 | B | `lib/cmd_gc.sh`, `test/gc.bats` | B2 1–7 | ~160 | U-A |
| U-B3 | B | `lib/cmd_status.sh`, `test/status.bats` (new) | B3 1–7 | ~145 | U-A |
| U-B4 | B | `lib/cmd_new.sh`, `lib/cmd_launch.sh`, `test/new.bats`, `test/launch.bats` (new) | B4 1–10 | ~275 | U-A (the dry-run no-fetch assertion lives in U-B6) |
| U-B5 | B | `lib/cmd_merge.sh`, `lib/cmd_init.sh`, `test/merge.bats`, `test/init.bats` (new) | B5 1–8 | ~160 | U-A |
| U-B6 | B | `lib/config.sh`, `lib/pm.sh`, `lib/cmd_doctor.sh`, `test/config.bats`, `test/doctor.bats` (new), `test/pm.bats` | B6 1–7 | ~170 | U-A |
| U-B7 | B (last) | `README.md`, `SKILL.md`, `CHANGELOG.md`, `docs/demo.cast`, `share/completions/*` | B7 | ~70 | U-B1..B6 merged |
| U-C1 | C (serial) | everything C1, C3 and C4 touch: common.sh, bin, cmd_merge, cmd_doctor, config.sh, cmd_gc, cmd_status, their tests, README/SKILL/CHANGELOG lines | C1 → C4 → C3, one commit each | ~220 | Wave B merged; operator decisions for C1 and C3 |
| U-C2 | C (serial, after U-C1) | everything C2 and C5 touch: cmd_gc, config.sh, pm.sh, cmd_doctor, cmd_init, cmd_new.sh:142 (read-only check), tests, SKILL/README/docs/completions/CHANGELOG, `WH_VERSION` bump to 0.3.0 | C2 → C5, one commit each, then the release commit | ~245 | U-C1 merged; operator decisions for C2 and C5 |

**Parallelism:**
- U-B1..U-B6 have pairwise-disjoint file sets and can run concurrently once U-A lands.
- U-B7 and the Wave C units overlap the shared docs and CHANGELOG, so they run one at a time.
- U-C1 can start on C1 and C4 while the C3 decision is pending; C4 needs no decision.

### 6.1 Round 2 sizing (supersedes the totals above)

Same method: every LOC figure is **estimated** by counting the lines each listed change adds or edits, using the code read for this plan (install.sh is 54 lines, `wc -l`, measured). Tests count at ~8–15 lines per bats case.

| Wave | LOC (est.) | Change vs round 1 |
|---|---|---|
| A | ~480 (A.1/A.2 ~300 + A.3 ~180) | +180 |
| B | ~2,270 (B1 240, B2 235, B3 235, B4 350, B5 195, B6 180, B7 130, B8 350, B9 355) | +1,140 |
| C | ~680 (C1 60, C2 170, C3 90, C4 82, C5 130, C6 40, C7 110) | +222 |
| **Total** | **~3,430** | **+1,540** |

### 6.2 Round 2 implementer units (each under 500 LOC; files exclusive while a unit runs; units that share a file are serial)

| Unit | Wave | Owns (exclusive) | Items | LOC (est.) | Depends on |
|---|---|---|---|---|---|
| U-A1 | A | as U-A above | A.1, A.2 | ~300 | none |
| U-A2 | A (serial after U-A1) | `lib/common.sh`, `test/common.bats`, `test/helper.bash` | A.3 1–8 + its tests | ~180 | U-A1 merged |
| U-B1 | B | `bin/worktree-harness`, `test/dispatcher.bats` | B1 1–9 | ~240 | U-A2; merge after U-B3 |
| U-B2 | B | `lib/cmd_gc.sh`, `test/gc.bats` | B2 1–12 | ~235 | U-A2 |
| U-B3 | B | `lib/cmd_status.sh`, `test/status.bats` | B3 1–12 | ~235 | U-A2 |
| U-B4 | B | `lib/cmd_new.sh`, `lib/cmd_launch.sh`, `test/new.bats`, `test/launch.bats` | B4 1–13 | ~350 | U-A2 |
| U-B5 | B | `lib/cmd_merge.sh`, `lib/cmd_init.sh`, `test/merge.bats`, `test/init.bats` | B5 1–10 | ~195 | U-A2 |
| U-B6 | B | `lib/config.sh`, `lib/pm.sh`, `lib/cmd_doctor.sh`, `test/config.bats`, `test/doctor.bats`, `test/pm.bats` | B6 1–9 | ~180 | U-A2 |
| U-B8 | B | `install.sh`, `test/install.bats`, `.github/workflows/ci.yml`, `CONTRIBUTING.md`, `.github/PULL_REQUEST_TEMPLATE.md` | B8 1–14 | ~350 | none in code (install.sh sources nothing); fires with U-B1..U-B6; needs D-R2-2/3/5/6/7/8 |
| U-B7 | B (after U-B1..B6, U-B8) | `README.md`, `SKILL.md`, `CHANGELOG.md`, `docs/demo.cast`, `docs/DESIGN.md`, `share/completions/*` | B7 + R2 additions | ~130 | U-B1..B6, U-B8 merged into `cli-bp/wh-wave-b` |
| U-B9 | B (last) | `lib/help_meta.sh` (new), `test/help.bats` (new), `test/presentation.bats` (new), `bin/worktree-harness` (help arm), README help row, CHANGELOG Added lines | B9 1–5 | ~355 | U-B7 merged; D-R2-9 |
| U-C1 | C (serial) | as above, plus C4's R2 pty test | C1 → C4 → C3 | ~232 | Wave B PR merged to `main`; decisions C1, C3 |
| U-C3 | C (serial, after U-C1) | `install.sh`, `test/install.bats`, README.md install section, CHANGELOG.md | C6 → C7, one commit each | ~150 | U-C1 merged; D-R2-4 |
| U-C2 | C (serial, after U-C3) | as above, plus `lib/common.sh`, `bin/worktree-harness` (`--non-interactive`), `lib/help_meta.sh` and `share/completions/*` (`--yes`, `--non-interactive`, so B9's drift tests stay green) | C2 → C5 → release commit | ~305 | U-C3 merged; decisions C2, C5 |

**Round 2 parallelism:**
- U-B1..U-B6 and U-B8 have pairwise-disjoint file sets (checked against the table above) and run concurrently once U-A2 lands.
- U-B7 and then U-B9 are serial: both touch README/CHANGELOG, and U-B9 also touches bin after U-B1.
- U-C1, U-C3 and U-C2 are serial (shared README/CHANGELOG; U-C2 ships the release commit last).

### 6.3 Round 2b sizing (supersedes 6.1)

Same method: every LOC figure is **estimated** by counting the lines each listed change adds or edits, with bats cases at ~9 lines. The second install.sh audit overlaps the first, so merged findings add only their corrections, not a second implementation.

| Wave | LOC (est.) | Change vs 6.1 |
|---|---|---|
| A | ~560 (A.1/A.2 ~300 + A.3 ~260) | +80 |
| B | ~3,000 (B1 250, B2 240, B3 235, B4 350, B5 200, B6 180, B7 175, B8 460, B10 390, B11 165, B9 355) | +730 |
| C | ~840 (C1 60, C2 175, C3 90, C4 82, C5 130, C6 70, C7 175, C8 55) | +160 |
| **Total** | **~4,400** | **+970** |

If D-R2-15 is (b), U-B11 shrinks to ~15 LOC and the total to ~4,250. D-R2-16 (b) and D-R2-18 (b) would each add ~25–40 LOC (estimated).

### 6.4 Round 2b implementer units (supersedes 6.2; each under 500 LOC)

| Unit | Wave | Owns (exclusive while it runs) | Items | LOC (est.) | Depends on |
|---|---|---|---|---|---|
| U-A1 | A | `lib/common.sh`, `test/common.bats`, `test/helper.bash`, `bin/worktree-harness` (2-line hook after :79 only) | A.1, A.2 | ~300 | none |
| U-A2 | A (serial after U-A1) | `lib/common.sh`, `test/common.bats`, `test/helper.bash` | A.3 1–12 + its tests | ~260 | U-A1 merged |
| U-B1 | B | `bin/worktree-harness`, `test/dispatcher.bats` | B1 1–10 | ~250 | U-A2; merge after U-B3 |
| U-B2 | B | `lib/cmd_gc.sh`, `test/gc.bats` | B2 1–12 | ~240 | U-A2 |
| U-B3 | B | `lib/cmd_status.sh`, `test/status.bats` | B3 1–12 | ~235 | U-A2; D-R2-16 |
| U-B4 | B | `lib/cmd_new.sh`, `lib/cmd_launch.sh`, `test/new.bats`, `test/launch.bats` | B4 1–13 | ~350 | U-A2 |
| U-B5 | B | `lib/cmd_merge.sh`, `lib/cmd_init.sh`, `test/merge.bats`, `test/init.bats` | B5 1–10 | ~200 | U-A2 |
| U-B6 | B | `lib/config.sh`, `lib/pm.sh`, `lib/cmd_doctor.sh`, `test/config.bats`, `test/doctor.bats`, `test/pm.bats` | B6 1–9 | ~180 | U-A2 |
| U-B8 | B | `install.sh`, `test/install.bats`, `test/install_helper.bash`, `.github/workflows/ci.yml`, `CONTRIBUTING.md`, `.github/PULL_REQUEST_TEMPLATE.md` | B8 1–5, 7, 13–20 | ~460 | none in code (install.sh sources nothing); D-R2-2, D-R2-3, D-R2-7 |
| U-B10 | B (serial after U-B8) | `install.sh`, `test/install_output.bats` | B8 6, 8–12; B10 1–5 | ~390 | U-B8 merged; D-R2-5, D-R2-6, D-R2-8, D-R2-13, D-R2-14 |
| U-B11 | B (serial after U-B10) | `install.sh`, `test/install_json.bats` | B11 1–6 | ~165 | U-B10 merged; D-R2-15 |
| U-B7 | B (after U-B1..B6, U-B11) | `README.md`, `SKILL.md`, `CHANGELOG.md`, `docs/demo.cast`, `docs/DESIGN.md`, `docs/THREAT_MODEL.md`, `share/completions/*` | B7 + R2 + R2b additions | ~175 | those merged into `cli-bp/wh-wave-b`; D-R2-19 |
| U-B9 | B (last) | `lib/help_meta.sh`, `test/help.bats`, `test/presentation.bats`, `bin/worktree-harness` (help arm), README help row, CHANGELOG Added lines, `CONTRIBUTING.md` Layout row | B9 1–5 | ~355 | U-B7 merged; D-R2-9 |
| U-C1 | C (serial) | as in 6.2 | C1 → C4 → C3 | ~232 | Wave B PR merged to `main`; decisions C1, C3 |
| U-C3 | C (serial, after U-C1) | `install.sh`, `test/install.bats`, `test/install_output.bats`, `.github/workflows/ci.yml` (`:60`), README.md install section, CHANGELOG.md | C6 → C7 → C8, one commit each | ~300 | U-C1 merged; D-R2-4, D-R2-12 |
| U-C2 | C (serial, after U-C3) | as in 6.2, plus the install.sh version constant if D-R2-2 is (b) | C2 → C5 → release commit | ~310 | U-C3 merged; decisions C2, C5; D-R2-18 |

**Round 2b parallelism:**
- U-B1..U-B6 and whichever of U-B8, U-B10, U-B11 is current have pairwise-disjoint file sets, and run concurrently once U-A2 lands.
- `install.sh` is the one file the three install units can't divide: `curl | sh` needs a single script, so they are serial. Each has its own test file, and U-B8 alone owns the CI and contributor-doc edits. Splitting them this way keeps every unit under the ceiling (the single-unit estimate was ~1,015 LOC).
- U-B7 and then U-B9 are serial, as are U-C1, U-C3 and U-C2 (shared README and CHANGELOG; U-C2 ships the release commit last).

---

## 7. Round 2 changes

**Inputs integrated:**
- 15 verified install.sh findings (F22–F36). install.sh was unaudited in round 1 (critic2 `uncoveredClis[5]`).
- Every worktree-harness entry in `/tmp/cli-bp/critic2.json`. Each was checked statically against `main` @ `b586f99`; nothing under audit was executed.
- `missedFindings[6,7,8,11]` became F37–F40.
- The `unmentionedRules` and `planConflicts` entries are either fixed below or recorded as verified-no-change in Section 5.

**Plan rows corrected (they contradicted the checklist or the repo's PR gate):**
1. **A.1 `wh_usage_die`**: `See: <cmd>` on one line becomes headline, blank line, `See all options:`, indented command (R105/R084). Test assertions in A.2, B1 and B4 were updated.
2. **A.1 `-C` built-in**: becomes `--cwd <DIR>`, with `-C` kept only for compatibility (R466/R062, F38). The A.1 `wh_require_repo` hint becomes `--cwd <DIR>` (R099).
3. **A.1 rich `wh_step "→"`**: becomes a blank gutter with `…` progress copy (R182/R220/R205).
4. **Wave B keep-substring list**: drops `"unknown global flag"`/`"unknown command"` in favour of the Reference J headlines (R060/R084). The test updates belong to U-B1.
5. **Wave B help rules**: Usage/Options/Global Options/Examples/Notes/Learn more order, `<UPPER_CASE>` placeholders, 1–3 parsed examples per leaf, env vars in Notes (R087/R091/R093/R100/R101/R102/R231/R079).
6. **B1-2**: drops the "run --help" hint (R096) and the `ENVIRONMENT` section (R087). Adds `(default)` on `help` (R088), task grouping (R096), and a `Learn more:` URL (R092).
7. **B2-6**: superseded by B2-10, so removed paths go on stdout only on exit 0 (R176).
8. **B5 row 6's single init Example**: now two examples, both parser-tested (R100; critic `missedFindings[11]`).
9. **Landing flow**: Wave B lands on `cli-bp/wh-wave-b` and reaches `main` in one PR with its docs, because `CONTRIBUTING.md:33-34` and the PR template :11 win over round 1's docs-last ordering.

**Sections and rows added:**
- **Header and index:** Phase 0 rows, graph, spawn steps and branches for U-A2/U-B8/U-B9/U-C3. Header rows for round-2 coverage, inputs and the gate conflict. Finding index F22–F40. Round 2 gates (`shellcheck -s sh install.sh`, `sh -n`/`dash -n`, help-does-no-work CI step).
- **A.3** (8 helper rows and 11 tests): `--cwd`, `--version` at any depth, `wh_deprecated` once per run, the `--help --json` hook, the blank progress gutter, the parse-only hook and `assert_help_examples_parse` (R100), the JSON error writer with its reason registry and pretty/compact output (R243–R264), and the guidance helpers (R238/R240).
- **B1 7–9**: `-v`/`--cwd`, parse-only in bin, and `help` extension routing.
- **B2 8–12**: full paths (F37), one label set (F39), R176, R326 and Examples.
- **B3 8–12**: `--fields` (R252), `wh_json_out` (R251), JSON failures (R253), Examples, and the schema handed to B9.
- **B4 11–13**: `new`/`launch` cross-reference (R473), guidance gating (R238), Examples. Its tests add child exit 42 and argv passthrough (R400) and typo-creates-nothing (R394).
- **B5 9–10**: quoted branch in recovery commands (R103), Examples.
- **B6 8–9**: the `invalid_config` reason, Examples.
- **B7 additions**: the glossary in `docs/DESIGN.md` (R423), `--cwd`/`-v` in README and completions, `<UPPER_CASE>` docs, demo.cast labels, and the install README section with exact uninstall commands.
- **New B8**: install.sh, 14 rows and 19 tests (F22–F25, F27, F28, F30–F36).
- **New B9**: help metadata (R106/R107/R108), drift guards for help, parser and completions (R087/R063/R109), and presentation tests (R401/R404).
- **C2 additions**: `--non-interactive` (R062/R409), the R403 mode matrix, full-path preview rows, the `--yes` example, and a test that `--force` never implies `--yes`.
- **C4 addition**: a pty test (R403).
- **New C6**: install.sh stdout holds only the path (F29).
- **New C7**: install ownership and `--force` (F26, DECISION D-R2-4).
- **Section 5**: round-2 refuted sub-claims, and the critic entries verified as needing no change.
- **5.1**: 12 round-2 conflict resolutions.
- **6.1/6.2**: sizing and the implementer split.

**Sizing:**
- **Total**: ~1,890 to ~3,430 LOC (estimated).
- **Implementer sessions**: 10 to 14. Every unit is under 500 LOC; the largest are U-B9 (~355), U-B4 (~350) and U-B8 (~350).
- **Parallel set**: U-B1..U-B6 and U-B8, which are file-disjoint.

**Needs decision (round 2).** The lead may apply each recommendation if the operator defers. Round-1 decisions C1, C2, C3 and C5 are unchanged.

| ID | Question | Options (recommended first) |
|---|---|---|
| D-R2-1 | `-C` and `-V` sit outside the short-option table (R466/R062) | (a) Add `--cwd`/`-v` now and make `-C`/`-V` deprecated aliases (`wh_deprecated`, once per run), removed in the next major-equivalent. (b) Keep `-C` as a reserved letter because it mirrors `git -C` (R466 allows reserving a letter with a CLI-wide reason; record it in docs/DESIGN.md) and keep `-V` as a silent alias. `--cwd` and `-v` become canonical either way. **R2b:** under (a), removing `-C` also needs `Formula/worktree-harness.rb:40` changed first |
| D-R2-2 | install.sh `--version` (R086) | (a) Reject it as an unknown option (exit 2) with a pointer to `worktree-harness --version`. (b) Print the checkout's `WH_VERSION`; this only works when run from a checkout. **R2b: the recommendation changes; see Section 8** |
| D-R2-3 | install.sh `--prefix <DIR>` | (a) Add it; it beats `WORKTREE_HARNESS_PREFIX` (R073). (b) Env var only, documented in `--help`. **R2b:** C7's destructive branch needs (a) for R156; (b) turns that into a recorded exception |
| D-R2-4 | C7 install ownership | (a) Refuse foreign paths, add `--force`, and add Installed/Replaced/already-installed receipts. (b) Receipts only, keeping silent replacement. Tier for replacing its own tree: ordinary (no prompt) vs destructive (`--yes` when it exists). **R2b:** receipts now land in B10-4 either way. (a) means refusal plus `--force --yes --prefix` (C7 R2b); (b) means no refusal |
| D-R2-5 | Guidance-disable variable name (R238; one variable for the CLI and install.sh, R009) | (a) `WH_GUIDANCE_DISABLED`, matching the CLI's runtime prefix (`WH_NO_FETCH`, `WH_NO_COLOR`). (b) `WORKTREE_HARNESS_GUIDANCE_DISABLED`, the installer's prefix |
| D-R2-6 | Progress glyph (R182) | (a) Blank gutter plus `…` in lib/common.sh and install.sh. (b) Keep the repo's `→` in rich mode only, recording the deviation from R182 |
| D-R2-7 | `WORKTREE_HARNESS_PREFIX` set but empty (R074) | (a) Document "empty means the default" (compatible). (b) Reject it with exit 2 |
| D-R2-8 | install.sh "get started" steps | (a) Treat them as next steps: always shown unless guidance is disabled (R235/R238). (b) Gate them with the optional offers (TTY, no CI) (R240) |
| D-R2-9 | Completions from shared metadata (R109) | (a) Drift tests against `lib/help_meta.sh` (B9-4). (b) Generate the three completion files from the metadata |
| D-R2-10 | Docs-in-PR gate (CONTRIBUTING.md:33-34) | (a) Integration branch `cli-bp/wh-wave-b`, one PR to `main`. (b) Each B unit edits its own README/SKILL rows and CHANGELOG line in its own PR. That gives up exclusive docs ownership, and shared-file conflicts are resolved by rebase |
| D-R2-11 | R243: `--json` for `new`/`merge`/`gc`/`init`/`doctor` was not scoped in either round | (a) Defer to a 0.4.0 plan. (b) Add it now (~250 LOC, estimated from B3's JSON rows × 5 commands) |

---

## 8. Round 2 changes (second integration: F41–F58)

Section 7 records the first round-2 integration and is unchanged except for the notes marked R2b in its decision table. Everything added this time is labelled **R2b**.

**Inputs integrated:**
- 18 verified findings from the second install.sh audit. Their verdicts rate 14 compatible and 4 breaking (F42, F44, F47, F48), and 14 of the 18 overlap F22–F36, so they merge rather than double-count. New work: F50, F53, F56, F58.
- Every worktree-harness entry in `critic2.json`, re-checked by static reading at `main` @ `b586f99`. Nothing under audit was executed, and no repo was changed. Section 5 lists the generic entries round 2 hadn't recorded (`unmentionedRules[1,14,18,23,25,26,29,30,33,34,35,36,38,41]`).

**Plan rows corrected (they contradicted the checklist, a repo gate, or a caller):**
1. **B8-4** couldn't land: no `mkdir -p` before the stage's `mktemp -d` would break `ci.yml:60`; 0700 mode; `mv` onto `$OLD` nests (F43).
2. **B8-6** changed a non-zero exit code in Wave B against the wave's own rule, removed typed credentials (F44's "breaking"), put git's text in the headline (R278, R297) and printed a chained recovery (R105). The exit code and prompt default move to the new C8.
3. **B8-7's sed** leaks part of a password containing `@` (F55, measured).
4. **B8-2's** `at <short commit>` can't print before the clone (F45).
5. **B8-9's** `[ -t 1 ]` contradicts R113 and R240 (F48); now D-R2-13.
6. **B8-11's** hand-padded rows contradict R181's 16-character label column.
7. **C7's** `--force` alone contradicts R146, R153 and R156 (F42); its recognition signature matches a git checkout; its refusal and recovery copy are replaced.
8. **C6's** unconditional stdout line contradicts R173's TTY clause (F47).
9. **A.1's** `doesn't take a value` contradicts R068 (A.3-9). **A.3-7's** no-op warnings contradict R309 (A.3-10). **A.3-8** lacked the stdin check (R113).
10. **B2-10, B5-3, B5-8** print the identifier on an interactive TTY too (R173; A.3-11).
11. **B3-1, B3-2 and B7's completions** taught `status --human`, a second format selector (R438). It stays accepted and unadvertised (D-R2-16).
12. **Round 2 gates, B8-14:** the install.sh lint is its own step, not part of the `ci.yml:23` list (`.shellcheckrc:8`).
13. **Caller facts:** Landing flow item 6, B1-7 and C6 said the Homebrew test uses only `--version`. It also runs `-C` (`Formula/worktree-harness.rb:40`) and pins the `worktree-harness <v>` bytes (`:36`).
14. **D-R2-2's recommendation** rejected `--version` with no documented reason to drop R086; it now prints the version from a pinned constant.

**Rows and sections added:**
- **Phase 0:** rows for U-B8's new goal, U-B10 and U-B11; graph; branches; spawn step 8; session budget.
- **Header:** coverage, inputs, and the caller correction. **Index:** F41–F58. **Landing flow:** item 9.
- **A.3 rows 9–12** and 5 tests: booleans, warnings in JSON, `wh_print_id`, the R408 lint.
- **B1-10** and 1 test (R068).
- **B7 R2b:** threat model (F58), install variables (F54), offers in README, the download-then-run form (F56), upgrade path, an R422 Exceptions section.
- **B8 rows 15–20** and 16 tests: help first, `main()` wrapper, source validation and fresh-prefix swap, phases and signals, `--` on the clone, test fixture and characterization tests.
- **New B10** (U-B10): clone failure block, `fail` helper and preflight, PATH states and state-checked next steps, fresh/replaced/unchanged receipts, closed-stream guard; 16 new tests plus 4 moved from B8.
- **New B11** (U-B11): `--json`, 6 rows and 10 tests.
- **C2 R2b:** R068 cases and the R156 pointer. **C6 R2b:** stdout gate, `say` on stderr, CI assertion, 4 tests. **C7 R2b:** per-path recognition, consent ladder, 12 new tests and 1 amended. **New C8:** exit 128 → 1, prompt default, dash-leading URL, quoted `~`.
- **Section 5:** F41–F58 sub-claims refuted or narrowed, and the extra critic entries. **5.1:** 17 conflict resolutions. **6.3, 6.4:** sizing and split.

**R100 (parser test for every new help example).** This round adds two examples, both to install.sh help: `    sh install.sh --json` and `    sh install.sh --prefix <DIR> --force --yes`. Each is added to `every --help example parses`, which also asserts the extracted list contains it, so it can't be skipped silently. Printed recovery commands are tested the same way (`the printed rerun parses`, and B10's preflight recovery). No new CLI help examples were added; the ones from the first integration are already covered by `assert_help_examples_parse`.

**Sizing:**
- **Total:** ~3,430 to ~4,400 LOC (estimated).
- **Implementer sessions:** 14 to 16, every one under 500 LOC. The largest are U-B8 (~460), U-B10 (~390) and U-B9 (~355).
- **Parallel set:** U-B1..U-B6 plus the current install.sh unit. `install.sh` is the one shared file, so U-B8, U-B10 and U-B11 are serial.

**Checked for this round (measured, on a toy, not install.sh):** `/tmp/cli-bp/wh_r2b_probe.sh` holds B8-15's help scan and parser, B10-1's clone block and B10-5's `say`. `sh -n`, `dash -n` and `shellcheck -s sh` all exit 0. Under both `sh` and `dash`: `--bogus --help` and `help` exit 0; `-- --help`, `--prefix=`, a trailing `--prefix` and `--dry-run` exit 2; a missing repo exits 128 with one headline and a Detail row; `user:p@ss@127.0.0.1:9` never prints `ss@`; a closed stdout doesn't abort the run before the clone.

**Not verified (static reading can't reach these):** external `curl | sh` users, so exit and stream changes rely on CHANGELOG notes; prompts on `/dev/tty` (reasoned from git's documented `GIT_TERMINAL_PROMPT`, not reproduced); network-side clone behaviour. Other probes cited above are the verifiers' measurements on stand-ins. install.sh and the CLI weren't run in this round.

**Needs decision (round 2b).** The lead may apply each recommendation if the operator defers. D-R2-1, D-R2-3 and D-R2-4 carry notes in Section 7.

| ID | Question | Options (recommended first) |
|---|---|---|
| D-R2-2 (amended) | install.sh `--version` (R086; nothing in the repo documents a reason to deviate) | (b′) Print the version from a constant in install.sh, pinned to `lib/common.sh:12` by a test. It works under `curl \| sh`, needs no clone (R012, R083), and adds one line to bump at release. (a) Reject it as unknown (exit 2) with a pointer to `worktree-harness --version`, recorded as an R422 exception. Section 7's checkout-only (b) is dropped: `$SRC` doesn't exist under `curl \| sh` before a clone |
| D-R2-12 | Quoted `~` in `WORKTREE_HARNESS_PREFIX` (R013, R074; exit 0 → 2 is contract per guidelines.md:1213) | (a) Reject it with exit 2 and a CHANGELOG entry (C8). That input only ever produced a literal `~` directory and a dead link, so the exit 0 was a false success. (b) No rejection: it resolves like any relative path, the link works, and the literal `~` directory stays |
| D-R2-13 | Optional shell-integration and completion offers under `curl \| sh` (R240, R113, R239) | (a) Show them only when `[ -t 0 ] && [ -t 2 ]`, `CI` unset and guidance on, so `curl \| sh` never does. B7 must first add the zsh `fpath` and fish steps to README, which exist only at install.sh:52. (b) Keep them in all modes except CI and guidance off, because `curl \| sh` is the primary install path, with an R422 exception for R240 and for R239's once-per-user clause, since install.sh keeps no per-user state |
| D-R2-14 | What the clone installs by default (SECURITY.md:10 says only the latest released tag receives fixes; `main` equals `v0.2.0` today, measured) | (a) Keep tracking `main`. Document that re-running upgrades, reconcile SECURITY.md:10, and keep `WORKTREE_HARNESS_REF` as the opt-in pin. Smallest change, and callers keep today's source. (b) Install the latest tag, resolved with `git ls-remote --tags --refs --sort=-v:refname` (git ≥ 2.18), with a fallback for forks with no tags. It matches SECURITY.md:10 but changes what gets installed, so it needs a Wave C item |
| D-R2-15 | install.sh `--json` (R243, F53) | (a) Add it (B11). Sub-choice for R252 `--fields`: an R422 exception, since the document has two fields and an outcome (recommended), or implement it (~15 LOC). (b) Record an R422 exception for R243 on install.sh: reason, user impact, test. The contract is then exit code plus the deterministic `$PREFIX/bin/worktree-harness` path, as `ci.yml:60-61` already uses, plus C6's stdout line. No bare path exists before C6 |
| D-R2-16 | `status --porcelain` and `--human` vs R438, R009 (`--porcelain` is documented at `lib/cmd_status.sh:6-7, :15`, README.md:240, SKILL.md:38; `--human` only at the case arm, `:23`) | (a) Keep `--porcelain` taught and `--human` accepted but unadvertised, with an R422 exception. No caller breaks; new scripts are taught `--json`. (b) Deprecate both through `wh_deprecated` in 0.3.0 and remove them in the next major-equivalent, updating README, SKILL and completions (~25 LOC, estimated). No parser exists in the repo or `~/.claude` (verifier grep, C3), but external scripts can't be checked |
| D-R2-17 | CLI `--version` output vs R086 "prints only the version" | (a) Keep `worktree-harness <v>` with an R422 exception: `Formula/worktree-harness.rb:36` and `test/dispatcher.bats:5-7` pin it. (b) Print bare `<v>` in a major-equivalent, changing the formula and the test in the same release |
| D-R2-18 | C2's `gc --prune --yes` removes an inferred set (R156; R151 allows it) | (a) Treat the set as fully determined by local state, keep the preview printing even with `--yes`, and record an R422 exception for R156. (b) Add `gc --prune [<PATH>]...` and require paths non-interactively, so agents pass what a person approved. That breaks the automation form C2 teaches (~40 LOC, estimated) |
| D-R2-19 | Rule for F58 (R008's check is about sibling surfaces, and targeted greps found no checklist row on doc accuracy) | (a) File it as a documentation defect with no guideline rule. (b) Keep it under R008. The docs edit is the same either way |

---

## 9. Execution record (session of 2026-11-06)

**Scope ruling (operator's brief for this session).** Wave A and every Wave B item land in full. Wave C lands only rows that need no operator decision. Every other contract-changing item keeps today's behaviour under decision packet `ad226c7513ea` (Keep): documented exit codes stay and are listed in help, `--yes` is an alias, preview-by-default stays, JSON shapes stay. No tag, no release, no `WH_VERSION` bump. The plan's "the lead may apply each recommendation" is replaced by this rule: where an open decision has an option that keeps today's behaviour, that option applies; where every option is additive (nothing exists today), the plan's recommendation applies. All of it is one filed class-B packet.

**Wave C under that ruling.**

| Item | Applied |
|---|---|
| C1 exit codes | **Kept.** `WH_EXIT_USAGE` stays 1, unknown command stays 64, merge conflict stays 2, doctor stays the issue count. Added: exit codes listed in root help and the affected command helps (U-B1, U-B5, U-B6); R337 exception in `docs/DESIGN.md` (U-B7) |
| C2 gc consent | **Kept.** `gc --prune` removes without a prompt. Added: `-y, --yes` accepted on `gc`; it never removes on its own (`gc --yes` previews, `gc --prune --yes` removes), so preview-by-default stays (U-B2). `--non-interactive` isn't added (R437). `wh_require_consent` ships in common.sh with no caller. R146 exception in `docs/DESIGN.md` |
| C3 unknown evidence | **Kept.** The B3 porcelain shim stays; gc doesn't refuse a guessed default branch. Exception recorded in `docs/DESIGN.md` |
| C4 piped status | **Lands** (no decision needed) |
| C5 fetch fails closed | **Kept.** B6's bounded warn-and-continue stays; PM and PORTS stay warnings. Exception recorded |
| C6 install.sh stdout | **Lands** (no decision needed) |
| C7 install ownership | **Kept** (D-R2-4 (b)): no refusal, no marker, no `--force`. Receipts land in B10-4 either way. Exception recorded |
| C8 install.sh exits | **Lands except the `~` rule** (the row's decision covers only that rule); D-R2-12 (b) keeps today's handling of a quoted `~` |

**Open decisions as applied.**

| ID | Applied | Why |
|---|---|---|
| D-R2-1 | (b): `--cwd` and `-v` are added and canonical; `-C` and `-V` stay silent and unadvertised, no deprecation warning | Keeps today; reason recorded in `docs/DESIGN.md` |
| D-R2-2 | (b′): `--version` prints a constant pinned to `lib/common.sh` by a test | Additive; today's "ignored, runs a reinstall" is F22 itself |
| D-R2-3 | (a): `--prefix <DIR>` added, beats the variable | Additive |
| D-R2-4 | (b) | Keeps today |
| D-R2-5 | (a): `WH_GUIDANCE_DISABLED` | Additive |
| D-R2-6 | (b): rich `wh_step` and install.sh progress keep `→`; R182 deviation recorded. Progress copy still moves to participles with `…`/`...` where no kept test substring depends on it | Keeps today |
| D-R2-7 | (a): empty means the default, documented | Keeps today |
| D-R2-8 | (a): get-started steps always shown unless guidance is off | Keeps today |
| D-R2-9 | (a): drift tests, no generation | Keeps today |
| D-R2-10 | Superseded: this brief says land one unit at a time, so B units land on `main` in dependency order rather than through `cli-bp/wh-wave-b`. Recorded conflict: `CONTRIBUTING.md:33-34` asks for docs in the PR that changes behaviour; docs land with U-B7 in the same run | Operator's brief |
| D-R2-11 | (a): deferred | Keeps today |
| D-R2-12 | (b): no rejection | Keeps today |
| D-R2-13 | (b): offers stay in all modes except CI and guidance off, with an R422 exception | Keeps today |
| D-R2-14 | (a): tracks `main`, `WORKTREE_HARNESS_REF` opt-in | Keeps today |
| D-R2-15 | (a): `--json` added, `--fields` is an R422 exception | Additive |
| D-R2-16 | (a): `--porcelain` taught, `--human` accepted and unadvertised | Keeps today |
| D-R2-17 | (a): `worktree-harness <v>` bytes stay | Keeps today |
| D-R2-18 | Not reached (C2 kept) | n/a |
| D-R2-19 | (a): filed as a documentation defect | No behaviour either way |
