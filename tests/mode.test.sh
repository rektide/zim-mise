#!/usr/bin/env bash

set -euo pipefail

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
module="$root/module"
bin="$root/bin"
mkdir -p "$module" "$bin"
cp init.zsh "$module/init.zsh"

cat >"$bin/mise" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  activate)
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

env -i HOME="$HOME" PATH="$bin:/usr/bin:/bin" zsh -dfc '
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_MODE == shims ]]
  [[ -z ${ZIM_MISE_TEST_HOOK:-} ]]
  (( ! $+functions[mise] ))
  [[ -f "$1/mise-shims.zsh" ]]
  [[ ! -e "$1/mise-activate.zsh" ]]
' zim-mise-test "$module"

env -i HOME="$HOME" PATH="$bin:/usr/bin:/bin" zsh -dfi -c '
  source "$1/init.zsh"
  [[ $ZIM_MISE_TEST_MODE == activate ]]
  [[ $ZIM_MISE_TEST_HOOK == 1 ]]
  (( $+functions[mise] ))
  [[ -f "$1/mise-activate.zsh" ]]
  [[ -f "$1/functions/_mise" ]]
' zim-mise-test "$module"

printf 'ok: interactive and non-interactive activation modes\n'
