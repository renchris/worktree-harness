#!/usr/bin/env bash
# test/helper.bash — shared fixtures for the bats suite.
# bats-core isolates each @test in its own subshell with a fresh BATS_TEST_TMPDIR.

WH_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
WH="$WH_ROOT/bin/worktree-harness"

# A throwaway repo: bare origin + working clone with a committed .harnessrc.
# Leaves cwd in the working clone. Exports ORIGIN, APP, WT_HOME.
make_repo() {
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  APP="$BATS_TEST_TMPDIR/app"
  WT_HOME="$BATS_TEST_TMPDIR/wt"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$APP"
  cd "$APP" || return 1
  git config user.email t@e.st
  git config user.name Tester
  git branch -M main 2>/dev/null || true
  printf '# app\n' > README.md
  printf '.env.local\n' > .gitignore
  printf 'SECRET=1\n' > .env.local
  cat > .harnessrc <<RC
HARNESS_BASE_POLICY="origin"
HARNESS_WORKTREE_HOME="$WT_HOME"
HARNESS_COPY=( ".env.local" )
HARNESS_PORTS=( "PORT=3000" )
HARNESS_MERGE_GATE="none"
RC
  git add -A
  git commit -qm init
  git push -q -u origin main
  git remote set-head origin main 2>/dev/null || true
}

# An empty scratch dir for pure-function tests (no git needed).
make_dir() { D="$BATS_TEST_TMPDIR/scratch"; mkdir -p "$D"; cd "$D" || return 1; }

# Commit a file ($2, default feat.txt) inside a worktree ($1).
commit_in() {
  local wt="$1" f="${2:-feat.txt}"
  ( cd "$wt" && printf 'x\n' > "$f" && git add "$f" && git commit -qm "feat: $f" )
}

# Print any bash-4+-only constructs found in REAL (non-comment) code lines of
# the bash sources. Empty output = clean. (zsh.sh / fish.fish are excluded —
# they intentionally use shell-specific syntax.)
find_bashisms() {
  grep -hvE '^[[:space:]]*#' \
    "$WH_ROOT"/bin/worktree-harness "$WH_ROOT"/lib/*.sh "$WH_ROOT"/share/shell/bash.sh \
    | grep -nE 'declare[[:space:]]+-A|local[[:space:]]+-A|mapfile|readarray|\[\[[[:space:]]+-v[[:space:]]|\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,)' \
    || true
}
