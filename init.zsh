# Makes Mise work in MSYS2/Cygwin; see
# https://github.com/jdx/mise/discussions/3961#discussioncomment-16024383
if [[ -n "$MSYSTEM" ]]; then
  () {
    local mise_binary_directory_path="$(/usr/bin/cygpath -u "$USERPROFILE")/scoop/shims"
    local mise_binary_path="${mise_binary_directory_path}/mise"
    [[ -x "$mise_binary_path" ]] || return

    if command -v mise.exe >/dev/null 2>&1; then
      _MISE_EXE_UNIX="$(/usr/bin/cygpath -u "$(command -v mise.exe)")"
    else
      _MISE_EXE_UNIX="${mise_binary_path}"
    fi
    mise() { command "$_MISE_EXE_UNIX" "$@"; }
    export MISE_EXE="$_MISE_EXE_UNIX"
    export MISE_SHELL=bash

    local cachedir=$1
    local command=$_MISE_EXE_UNIX

    # generating activation file (with path fixups for MSYS2)
    local activatefile=$cachedir/mise-activate.zsh
    if [[ ! -e $activatefile || $activatefile -ot $command ]]; then
      local mise_activate_script
      mise_activate_script="$($command activate zsh)"

      local mise_path_line
      mise_path_line="$(printf '%s\n' "$mise_activate_script" | sed -n 's/^export PATH="\([^"]*\)".*$/\1/p')"
      if [[ -n "$mise_path_line" ]]; then
        mise_path_line="$(/usr/bin/cygpath -u -p "$mise_path_line")"
        mise_activate_script="$(printf '%s\n' "$mise_activate_script" \
          | awk -v newpath="$mise_path_line" 'BEGIN{done=0} { if (!done && $0 ~ /^export PATH=/) { print "export PATH=\"" newpath "\""; done=1; } else { print $0; } }')"
      fi

      mise_activate_script="$(printf '%s\n' "$mise_activate_script" \
        | sed -E "s@[A-Za-z]:\\\\[^\"']*\\\\mise\.exe@$_MISE_EXE_UNIX@g")"

      print -r -- "$mise_activate_script" >| $activatefile
      zcompile -UR $activatefile
    fi

    source $activatefile
    source <($command hook-env -s zsh)

    # generating completions
    local compfile=$cachedir/functions/_mise
    [[ -d ${compfile:h} ]] || mkdir -p ${compfile:h}
    if [[ ! -e $compfile || $compfile -ot $command ]]; then
      $command complete --shell zsh >| $compfile
      print -u2 -PR "* Detected a new version of 'mise'. Regenerated completions."
    fi
    fpath+=(${compfile:h})

    # The generated chpwd hook can leave PATH in Windows form until the next
    # precmd. Normalise it immediately so later chpwd hooks see a Unix path.
    __mise_fix_path() {
      export PATH="$(/usr/bin/cygpath -u -p "$PATH")"
    }
    if (( $+functions[_mise_hook_chpwd] )); then
      functions[_mise_hook_chpwd_raw]=${functions[_mise_hook_chpwd]}
      _mise_hook_chpwd() {
        _mise_hook_chpwd_raw "$@"
        __mise_fix_path
      }
    fi

    # fix Windows-style paths after every prompt
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __mise_fix_path
    __mise_fix_path
  } ${0:h}

elif (( ${+commands[mise]} )); then
  () {
    local command=${commands[mise]}

    # generating activation file
    local activatefile=$1/mise-activate.zsh
    if [[ ! -e $activatefile || $activatefile -ot $command ]]; then
      $command activate zsh >| $activatefile
      zcompile -UR $activatefile
    fi

    source $activatefile
    source <($command hook-env -s zsh)

    # generating completions
    local compfile=$1/functions/_mise
    [[ -d ${compfile:h} ]] || mkdir -p ${compfile:h}
    if [[ ! -e $compfile || $compfile -ot $command ]]; then
      $command complete --shell zsh >| $compfile
      print -u2 -PR "* Detected a new version of 'mise'. Regenerated completions."
    fi
    fpath+=(${compfile:h})
  } ${0:h}
fi
