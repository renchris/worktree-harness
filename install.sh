#!/usr/bin/env sh
# install.sh — install worktree-harness. POSIX sh (works under `curl ... | sh`).
#
#   curl -fsSL https://raw.githubusercontent.com/renchris/worktree-harness/main/install.sh | sh
#   ./install.sh                      # from a checkout
#
# Layout: copies bin/ lib/ share/ to $PREFIX/share/worktree-harness and symlinks
# the dispatcher into $PREFIX/bin. Override the location with
# WORKTREE_HARNESS_PREFIX (default: ~/.local). No sudo, no global state.
set -eu

REPO_URL="${WORKTREE_HARNESS_REPO:-https://github.com/renchris/worktree-harness.git}"
PREFIX="${WORKTREE_HARNESS_PREFIX:-$HOME/.local}"
SHARE_DIR="$PREFIX/share/worktree-harness"
BIN_DIR="$PREFIX/bin"

# Install from the current checkout if there is one; otherwise clone.
SELF_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
CLEANUP=""
if [ -f "$SELF_DIR/bin/worktree-harness" ]; then
  SRC="$SELF_DIR"
else
  command -v git >/dev/null 2>&1 || { echo "install: git is required to clone $REPO_URL" >&2; exit 1; }
  TMP=$(mktemp -d)
  CLEANUP="$TMP"
  echo "→ cloning $REPO_URL"
  git clone --depth 1 "$REPO_URL" "$TMP/worktree-harness" >/dev/null 2>&1
  SRC="$TMP/worktree-harness"
fi

echo "→ installing to $SHARE_DIR"
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR" "$BIN_DIR"
cp -R "$SRC/bin" "$SRC/lib" "$SRC/share" "$SHARE_DIR/"
chmod +x "$SHARE_DIR/bin/worktree-harness"
ln -sf "$SHARE_DIR/bin/worktree-harness" "$BIN_DIR/worktree-harness"

[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"

echo "✓ installed: $BIN_DIR/worktree-harness"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "  add it to your PATH:   export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
echo
echo "  optional: auto-isolate your agent (bash/zsh/fish) by sourcing one of:"
echo "    $SHARE_DIR/share/shell/bash.sh"
echo "    $SHARE_DIR/share/shell/zsh.sh"
echo "    $SHARE_DIR/share/shell/fish.fish"
echo
echo "  optional: shell completions are under $SHARE_DIR/share/completions/"
echo "    (bash: source worktree-harness.bash · zsh: add the dir to fpath · fish: copy *.fish)"
echo
echo "  get started:   worktree-harness init  &&  worktree-harness new my-feature"
