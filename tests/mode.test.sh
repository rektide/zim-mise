#!/usr/bin/env bash

set -euo pipefail

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
bin="$root/bin"
mkdir -p "$bin"

cat >"$bin/mise" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  activate)
    printf 'export ZIM_MISE_TEST_ARGS="%s"\n' "$*"
    if [[ " $* " == *" --shims "* ]]; then
      printf 'export ZIM_MISE_TEST_MODE=shims\n'
    else
      printf 'export ZIM_MISE_TEST_MODE=activate\nmise() { command mise "$@"; }\n'
    fi
    ;;
  hook-env)
    printf 'export ZIM_MISE_TEST_HOOK=1\n'
    ;;
  complete)
    printf '#compdef mise\n'
    ;;
esac
EOF
chmod +x "$bin/mise"

# module <name> -- fresh copy of the module under $root/<name>
module() {
  mkdir -p "$root/$1"
  cp init.zsh "$root/$1/init.zsh"
}

# zsh_ok <label> <flags> <script> <module-dir>
# Runs: zsh <flags> -c <script> zim-mise-test <module-dir>; module dir is $1 in the script.
zsh_ok() {
  local label="$1"; shift
  local flags="$1"; shift
  local script="$1"; shift
  local dir="$1"; shift
  env -i HOME="$HOME" PATH="$bin:/usr/bin:/bin" \
    zsh $flags -c "$script" zim-mise-test "$dir"
  echo "ok: $label"
}

# --- defaults (no zstyles) ----------------------------------------------
module default

zsh_ok "non-interactive default is shims" -df '
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_MODE == shims ]]
  [[ -z ${ZIM_MISE_TEST_HOOK:-} ]]
  (( ! $+functions[mise] ))
  [[ -f "$1/mise-shims.zsh" ]]
  [[ ! -e "$1/mise-activate.zsh" ]]
' "$root/default"

zsh_ok "interactive default is full activate" -dfi '
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_MODE == activate ]]
  [[ $ZIM_MISE_TEST_HOOK == 1 ]]
  (( $+functions[mise] ))
  [[ -f "$1/mise-activate.zsh" ]]
  [[ -f "$1/functions/_mise" ]]
' "$root/default"

# --- mode=shims forced, even interactively -------------------------------
module shims

zsh_ok "mode=shims skips hooks even interactively" -dfi '
  zstyle ":zim:plugins:mise" mode shims
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_MODE == shims ]]
  [[ -z ${ZIM_MISE_TEST_HOOK:-} ]]
  (( ! $+functions[mise] ))
  [[ -f "$1/mise-shims.zsh" ]]
' "$root/shims"

# --- mode=activate forced, even non-interactively -------------------------
module forced

zsh_ok "mode=activate exports env in non-interactive shells" -df '
  zstyle ":zim:plugins:mise" mode activate
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_MODE == activate ]]
  [[ $ZIM_MISE_TEST_HOOK == 1 ]]
  (( $+functions[mise] ))
  [[ -f "$1/mise-activate.zsh" ]]
' "$root/forced"

# --- activate-args passthrough, cache bypassed ----------------------------
module args

zsh_ok "activate-args passed through, no cache file" -dfi '
  zstyle ":zim:plugins:mise" activate-args --status
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_ARGS == *--status* ]]
  [[ $ZIM_MISE_TEST_MODE == activate ]]
  [[ ! -e "$1/mise-activate.zsh" ]]
  [[ ! -e "$1/mise-shims.zsh" ]]
' "$root/args"

zsh_ok "activate-args keep --shims in non-interactive default mode" -df '
  zstyle ":zim:plugins:mise" activate-args --status
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_ARGS == *--status* ]]
  [[ $ZIM_MISE_TEST_ARGS == *--shims* ]]
  [[ $ZIM_MISE_TEST_MODE == shims ]]
' "$root/args"

# --- --no-hook-env skips the initial hook-env ------------------------------
module nohook

zsh_ok "--no-hook-env also skips initial hook-env" -dfi '
  zstyle ":zim:plugins:mise" activate-args --no-hook-env
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_MODE == activate ]]
  [[ -z ${ZIM_MISE_TEST_HOOK:-} ]]
' "$root/nohook"

# --- completions=no --------------------------------------------------------
module nocomp

zsh_ok "completions=no skips completion generation" -dfi '
  zstyle ":zim:plugins:mise" completions no
  source "$1/init.zsh"
  [[ ! -e "$1/functions/_mise" ]]
' "$root/nocomp"

# --- quiet ------------------------------------------------------------------
module quiet

quiet_err="$root/quiet.err"
env -i HOME="$HOME" PATH="$bin:/usr/bin:/bin" \
  zsh -dfi -c '
    zstyle ":zim:plugins:mise" quiet yes
    source "$1/init.zsh"
  ' zim-mise-test "$root/quiet" 2>"$quiet_err"
[[ ! -s "$quiet_err" ]] || { cat "$quiet_err" >&2; exit 1; }
echo "ok: quiet suppresses regeneration notice"

# --- unknown mode warns and falls back to auto ------------------------------
module bogus

bogus_err="$root/bogus.err"
env -i HOME="$HOME" PATH="$bin:/usr/bin:/bin" \
  zsh -dfi -c '
    zstyle ":zim:plugins:mise" mode bogus
    source "$1/init.zsh"
    [[ $ZIM_MISE_TEST_MODE == activate ]]
  ' zim-mise-test "$root/bogus" 2>"$bogus_err"
grep -q "unknown mode" "$bogus_err"
echo "ok: unknown mode warns and uses auto"
