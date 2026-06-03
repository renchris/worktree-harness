#!/usr/bin/env bats
load helper

setup() {
  # shellcheck source=../lib/pm.sh
  . "$WH_ROOT/lib/pm.sh"
}

@test "pnpm lockfile -> pnpm + --frozen-lockfile" {
  make_dir; touch pnpm-lock.yaml
  [ "$(wh_detect_pm "$PWD")" = "pnpm" ]
  [ "$(wh_pm_install_cmd pnpm "$PWD")" = "pnpm install --frozen-lockfile" ]
}

@test "package-lock.json -> npm ci" {
  make_dir; touch package.json package-lock.json
  [ "$(wh_detect_pm "$PWD")" = "npm" ]
  [ "$(wh_pm_install_cmd npm "$PWD")" = "npm ci" ]
}

@test "package.json with no lockfile -> npm install" {
  make_dir; touch package.json
  [ "$(wh_detect_pm "$PWD")" = "npm" ]
  [ "$(wh_pm_install_cmd npm "$PWD")" = "npm install" ]
}

@test "yarn classic -> --frozen-lockfile" {
  make_dir; touch yarn.lock
  [ "$(wh_detect_pm "$PWD")" = "yarn" ]
  [ "$(wh_pm_install_cmd yarn "$PWD")" = "yarn install --frozen-lockfile" ]
}

@test "yarn berry (.yarnrc.yml) -> --immutable" {
  make_dir; touch yarn.lock .yarnrc.yml
  [ "$(wh_pm_install_cmd yarn "$PWD")" = "yarn install --immutable" ]
}

@test "bun lockfile -> bun + --frozen-lockfile" {
  make_dir; touch bun.lockb
  [ "$(wh_detect_pm "$PWD")" = "bun" ]
  [ "$(wh_pm_install_cmd bun "$PWD")" = "bun install --frozen-lockfile" ]
}

@test "uv lockfile -> uv sync --frozen" {
  make_dir; touch uv.lock
  [ "$(wh_detect_pm "$PWD")" = "uv" ]
  [ "$(wh_pm_install_cmd uv "$PWD")" = "uv sync --frozen" ]
}

@test "requirements.txt -> pip" {
  make_dir; touch requirements.txt
  [ "$(wh_detect_pm "$PWD")" = "pip" ]
}

@test "Cargo.toml -> cargo fetch" {
  make_dir; touch Cargo.toml
  [ "$(wh_detect_pm "$PWD")" = "cargo" ]
  [ "$(wh_pm_install_cmd cargo "$PWD")" = "cargo fetch" ]
}

@test "go.mod -> go mod download" {
  make_dir; touch go.mod
  [ "$(wh_detect_pm "$PWD")" = "go" ]
  [ "$(wh_pm_install_cmd go "$PWD")" = "go mod download" ]
}

@test "empty dir -> none + empty install command" {
  make_dir
  [ "$(wh_detect_pm "$PWD")" = "none" ]
  [ -z "$(wh_pm_install_cmd none "$PWD")" ]
}

@test "lockfile precedence: pnpm beats package-lock" {
  make_dir; touch pnpm-lock.yaml package-lock.json package.json
  [ "$(wh_detect_pm "$PWD")" = "pnpm" ]
}
