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
    local -i full_activation=0
    local -a activate_args=(activate zsh)
    local activation_mode=shims
    if [[ -o interactive ]]; then
      full_activation=1
      activation_mode=activate
    else
      activate_args+=(--shims)
    fi

    # Keep distinct caches because .zshenv is sourced by both interactive and
    # non-interactive shells.
    local activatefile=$cachedir/mise-${activation_mode}.zsh
    if [[ ! -e $activatefile || $activatefile -ot $command ]]; then
      local mise_activate_script
      mise_activate_script="$($command "${activate_args[@]}")"

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
    (( full_activation )) || return
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

    # Module options, read via zstyle. Set them BEFORE this module loads
    # (in .zshenv when loading from the early Zim channel):
    #
    #   zstyle ':zim:plugins:mise' mode auto|shims|activate
    #       auto (default): full activate interactively, shims otherwise.
    #       shims: always `mise activate --shims`.
    #       activate: always full activation, even in non-interactive shells
    #                 (exports [env] vars to scripts; costs a mise run per shell).
    #   zstyle ':zim:plugins:mise' activate-args <arg>...
    #       Extra arguments appended to `mise activate`. Disables the
    #       activation cache (output depends on the arguments).
    #   zstyle ':zim:plugins:mise' completions yes|no   (default yes)
    #   zstyle ':zim:plugins:mise' quiet yes|no         (default no)
    local mode
    zstyle -s ':zim:plugins:mise' mode mode || mode=auto
    local -a extra_args
    zstyle -a ':zim:plugins:mise' activate-args extra_args
    local completions
    zstyle -s ':zim:plugins:mise' completions completions || completions=yes
    [[ $completions == (1|yes|true|on) ]] || completions=no
    local quiet
    zstyle -s ':zim:plugins:mise' quiet quiet || quiet=no
    [[ $quiet == (1|yes|true|on) ]] && quiet=yes || quiet=no
    if [[ $mode != auto && $mode != shims && $mode != activate ]]; then
      print -u2 -PR "* zim-mise: unknown mode '${mode}', using auto."
      mode=auto
    fi

    local -i full_activation=0
    local -a activate_args=(activate zsh "${extra_args[@]}")
    local activation_mode=shims
    if [[ $mode == activate ]]; then
      full_activation=1
      activation_mode=activate
    elif [[ $mode == auto && -o interactive ]]; then
      full_activation=1
      activation_mode=activate
    else
      activate_args+=(--shims)
    fi

    if (( ${#extra_args} )); then
      # Argument-dependent output is not cacheable; evaluate directly.
      source <($command "${activate_args[@]}")
    else
      # Keep distinct caches because .zshenv is sourced by both interactive and
      # non-interactive shells.
      local activatefile=$1/mise-${activation_mode}.zsh
      if [[ ! -e $activatefile || $activatefile -ot $command ]]; then
        $command "${activate_args[@]}" >| $activatefile
        zcompile -UR $activatefile
      fi
      source $activatefile
    fi

    (( full_activation )) || return
    # `--no-hook-env` in activate-args also opts out of this initial hook-env.
    (( ${extra_args[(I)--no-hook-env]} )) || source <($command hook-env -s zsh)

    if [[ $completions == yes ]]; then
      # generating completions
      local compfile=$1/functions/_mise
      [[ -d ${compfile:h} ]] || mkdir -p ${compfile:h}
      if [[ ! -e $compfile || $compfile -ot $command ]]; then
        $command complete --shell zsh >| $compfile
        [[ $quiet == yes ]] || print -u2 -PR "* Detected a new version of 'mise'. Regenerated completions."
      fi
      fpath+=(${compfile:h})
    fi
  } ${0:h}
fi
