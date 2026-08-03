#!/bin/bash
set -e

echo "⚠️  Starting dotfiles uninstall..."

# Determine platform.
OS_TYPE="$(uname -s)"
if [ -f /etc/redhat-release ]; then
    platform=redhat
else
    case "$OS_TYPE" in
        Linux*)  platform=linux ;;
        Darwin*) platform=mac ;;
        *) echo "❌ Unsupported platform: $OS_TYPE"; exit 1 ;;
    esac
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Keep in sync with FILES_TO_LINK in install.sh -- anything linked there but
# missing here is left behind by an uninstall.
FILES_TO_LINK=(
  ".zshrc"
  ".gitignore_global"
  ".gitconfig"
  ".claude/settings.json"
  ".claude/statusline-command.sh"
)

# Remove dotfile symlinks and restore backups.
echo "🧹 Removing dotfile symlinks..."
for filename in "${FILES_TO_LINK[@]}"; do
  target="$HOME/$filename"
  if [[ -L "$target" && "$(readlink "$target")" == "$DOTFILES_DIR/"* ]]; then
    echo "❌ Removing symlink: $target"
    rm "$target"

    if ls "$target".bak.* &>/dev/null; then
      latest_backup="$(find "$HOME" -maxdepth 1 -name "$(basename "$target").bak.*" -print | sort | tail -n 1)"
      echo "🔁 Restoring backup: $latest_backup → $target"
      mv "$latest_backup" "$target"
    fi
  fi
done

# Remove zsh plugins.
echo "🧹 Removing Zsh plugins..."
PLUGIN_NAMES=("zsh-syntax-highlighting" "zsh-autosuggestions" "pure")

if [[ "$platform" == "mac" ]]; then
  for plugin in "${PLUGIN_NAMES[@]}"; do
    if brew list "$plugin" &>/dev/null; then
      echo "🔧 Uninstalling $plugin..."
      if brew uninstall "$plugin" &>/dev/null; then
        echo "✅ $plugin uninstalled"
      else
        echo "⚠️  Could not uninstall $plugin (may be required elsewhere)"
      fi
    fi
  done
else
  for plugin in "${PLUGIN_NAMES[@]}"; do
    rm -rf "$HOME/.zsh/$plugin"
  done
  echo "✅ Removed manually installed Zsh plugins"
fi

# Remove zsh cache.
if [[ -d "$HOME/.zsh/cache" ]]; then
  rm -rf "$HOME/.zsh/cache"
  echo "✅ Removed Zsh cache"
fi

# Remove fzf
echo "🧹 Removing fzf..."
if [[ "$platform" == "mac" ]]; then
  if brew list fzf &>/dev/null; then
    brew uninstall fzf
    echo "✅ fzf removed (via Homebrew)"
  fi
else
  rm -rf "$HOME/.fzf"
  echo "✅ fzf removed (manually cloned)"
fi

# Snazzy reminder
echo "🎨 Snazzy terminal theme was not automatically reverted."
echo "📝 To fully remove it, manually switch or delete the profile in your Terminal settings."
echo "✅ Dotfiles uninstallation complete."