#!/usr/bin/env bash
# compat.sh — OS/shell portability shims so behavior is identical on macOS
# (BSD userland, bash 3.2) and Linux (GNU userland).
#
# We deliberately avoid tools whose flags differ across platforms — GNU-only
# `realpath`, `readlink -f`, `sed -i`, `stat -c`, `find -printf` — and bash 4+
# constructs (declare -A, mapfile/readarray, [[ -v ]], ${var^^}). `find -mmin`
# and `find -type f` ARE portable (BSD + GNU) and are used directly.

# True if $1 is an executable command on PATH.
wh_has() { command -v "$1" >/dev/null 2>&1; }

# Absolute, physical path of an EXISTING file or directory. Portable stand-in
# for `realpath` / `readlink -f`.
wh_abspath() {
  local target="$1" dir base
  if [ -d "$target" ]; then
    ( cd "$target" >/dev/null 2>&1 && pwd -P )
  else
    dir="$(dirname "$target")"
    base="$(basename "$target")"
    ( cd "$dir" >/dev/null 2>&1 && printf '%s/%s\n' "$(pwd -P)" "$base" )
  fi
}

# Real directory of a (possibly symlinked) path. Used so the dispatcher locates
# lib/ and share/ after install.sh symlinks bin/ into ~/.local/bin. Portable
# readlink loop — `readlink` with no flags behaves the same on macOS + Linux.
wh_resolve_dir() {
  local src="$1" dir
  while [ -h "$src" ]; do
    dir="$( cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd )"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  ( cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd )
}

# wh_os — "macos" | "linux" | "other".
wh_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)  echo linux ;;
    *)      echo other ;;
  esac
}
