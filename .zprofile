# Login-shell environment. Read once per login shell, before .zshrc.
typeset -U path PATH fpath

for __brew_prefix in ${HOMEBREW_PREFIX} /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
  [[ -x "$__brew_prefix/bin/brew" ]] || continue

  export HOMEBREW_PREFIX="$__brew_prefix"
  export HOMEBREW_CELLAR="$__brew_prefix/Cellar"
  if [[ -d "$__brew_prefix/Homebrew" ]]; then
    export HOMEBREW_REPOSITORY="$__brew_prefix/Homebrew"
  else
    export HOMEBREW_REPOSITORY="$__brew_prefix"
  fi

  path=("$__brew_prefix/bin" "$__brew_prefix/sbin" $path)
  fpath=("$__brew_prefix/share/zsh/site-functions" $fpath)
  export INFOPATH="$__brew_prefix/share/info:${INFOPATH:-}"
  break
done
unset __brew_prefix

[[ -d "$HOME/.local/bin" ]] && path=("$HOME/.local/bin" $path)