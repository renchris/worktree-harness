#!/usr/bin/env bash
# pm.sh — detect the package manager from lockfiles, and emit the matching
# install command using its reproducible/frozen variant. Detection keys off
# files in the repo root ($1). This is one of the tool's differentiators: no
# competitor auto-derives the frozen-lockfile command from the lockfile.

# wh_detect_pm <repo-root> → pnpm|bun|yarn|npm|uv|poetry|pipenv|pip|cargo|go|none
wh_detect_pm() {
  local r="$1"
  if [ -f "$r/pnpm-lock.yaml" ];     then echo pnpm;   return; fi
  if [ -f "$r/bun.lockb" ] || [ -f "$r/bun.lock" ]; then echo bun; return; fi
  if [ -f "$r/yarn.lock" ];          then echo yarn;   return; fi
  if [ -f "$r/package-lock.json" ] || [ -f "$r/npm-shrinkwrap.json" ]; then echo npm; return; fi
  if [ -f "$r/uv.lock" ];            then echo uv;     return; fi
  if [ -f "$r/poetry.lock" ];        then echo poetry; return; fi
  if [ -f "$r/Pipfile.lock" ];       then echo pipenv; return; fi
  if [ -f "$r/requirements.txt" ];   then echo pip;    return; fi
  if [ -f "$r/Cargo.toml" ];         then echo cargo;  return; fi
  if [ -f "$r/go.mod" ];             then echo go;     return; fi
  # package.json with no lockfile → npm is the conventional default JS manager.
  if [ -f "$r/package.json" ];       then echo npm;    return; fi
  echo none
}

# wh_pm_install_cmd <pm> <repo-root> → the install command string ("" for none).
wh_pm_install_cmd() {
  local pm="$1" r="$2"
  case "$pm" in
    pnpm)   echo "pnpm install --frozen-lockfile" ;;
    bun)    echo "bun install --frozen-lockfile" ;;
    yarn)   # Berry (.yarnrc.yml) uses --immutable; classic uses --frozen-lockfile.
            if [ -f "$r/.yarnrc.yml" ]; then echo "yarn install --immutable"
            else echo "yarn install --frozen-lockfile"; fi ;;
    npm)    # `npm ci` needs a lockfile; fall back to install when there isn't one.
            if [ -f "$r/package-lock.json" ] || [ -f "$r/npm-shrinkwrap.json" ]; then echo "npm ci"
            else echo "npm install"; fi ;;
    uv)     echo "uv sync --frozen" ;;
    poetry) echo "poetry install" ;;
    pipenv) echo "pipenv sync" ;;
    pip)    echo "pip install -r requirements.txt" ;;
    cargo)  echo "cargo fetch" ;;
    go)     echo "go mod download" ;;
    none|*) echo "" ;;
  esac
}

# wh_resolve_install <repo-root> → the install command to actually run, honoring
# HARNESS_INSTALL ("auto" derives from PM; "none" disables; anything else is a
# literal command) and HARNESS_PACKAGE_MANAGER ("auto" detects).
wh_resolve_install() {
  local r="$1" pm
  case "$HARNESS_INSTALL" in
    none) echo ""; return ;;
    auto) ;;
    *)    echo "$HARNESS_INSTALL"; return ;;
  esac
  if [ "$HARNESS_PACKAGE_MANAGER" = "auto" ]; then pm="$(wh_detect_pm "$r")"; else pm="$HARNESS_PACKAGE_MANAGER"; fi
  wh_pm_install_cmd "$pm" "$r"
}
