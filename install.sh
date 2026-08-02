#!/bin/bash
set -e

echo "🛠️  Starting dotfiles setup..."

# Determine OS type
OS_TYPE="$(uname -s)"
if [ -f /etc/redhat-release ]; then
    platform=redhat
else
    case "$OS_TYPE" in
        Linux*)     platform=linux;;
        Darwin*)    platform=mac;;
        *)          echo "Unsupported platform: $OS_TYPE"; exit 1;;
    esac
fi

# Set up dotfiles directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILES_TO_LINK=(
  ".zshrc"
  ".gitignore_global"
  ".gitconfig"
  ".claude/settings.json"
  ".claude/statusline-command.sh"
)

# Backup an existing file.
backup_file() {
  local file="$1"
  if [ -f "$file" ] || [ -L "$file" ]; then
    mv "$file" "${file}.bak.$(date +%s)"
    echo "🔁 Backed up existing $file"
  fi
}

# Install base packages.
install_packages() {
  
  echo "📦 Installing required packages..."
  if [[ "$platform" == "linux" ]]; then
    PKG_MGR="apt"
    INSTALL_CMD="sudo apt install -y"
    CHECK_CMD="dpkg -s"
    REQUIRED_PKGS=(git tree zsh curl)
    sudo apt update

  elif [[ "$platform" == "redhat" ]]; then
    PKG_MGR=$(command -v dnf &>/dev/null && echo "dnf" || echo "yum")
    INSTALL_CMD="sudo $PKG_MGR install -y"
    CHECK_CMD="rpm -q"
    REQUIRED_PKGS=(git tree zsh curl)
    sudo $PKG_MGR -y makecache

  elif [[ "$platform" == "mac" ]]; then
    REQUIRED_PKGS=(git tree) # curl and zsh are preinstalled and managed separately on macOS
    if ! command -v brew &>/dev/null; then
      echo "🍺 Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    PKG_MGR="brew"
    INSTALL_CMD="brew install"
    CHECK_CMD="brew list"
  fi

  # If running inside VMware, install guest tools.
  if [[ "$platform" == "linux" || "$platform" == "redhat" ]]; then
    if systemd-detect-virt 2>/dev/null | grep -qi vmware; then
      echo "🖥️  VMware VM detected; adding VMware guest tools..."
      REQUIRED_PKGS+=(open-vm-tools open-vm-tools-desktop)
    fi
  fi

  # Go through and install.
  for pkg in "${REQUIRED_PKGS[@]}"; do
    if $CHECK_CMD "$pkg" &>/dev/null; then
      echo "✅ $pkg already installed"
    else
      echo "📦 Installing $pkg..."
      $INSTALL_CMD "$pkg"
    fi
  done

  if [[ "$platform" == "linux" || "$platform" == "redhat" ]]; then
    if systemd-detect-virt 2>/dev/null | grep -qi vmware; then
      sudo systemctl enable open-vm-tools || true
      sudo systemctl restart open-vm-tools || true
    fi
  fi
}

# Install fzf
install_fzf() {
  echo "🔍 Installing fzf..."

  if [[ "$platform" == "mac" ]]; then
    if command -v fzf &>/dev/null; then
      echo "✅ fzf already installed"
    else
      brew install fzf
    fi

    FZF_INSTALL_SCRIPT="$(brew --prefix)/opt/fzf/install"
    if [[ -x "$FZF_INSTALL_SCRIPT" ]]; then
      echo "⚙️  Setting up fzf key bindings and completions..."
      "$FZF_INSTALL_SCRIPT" --key-bindings --completion --no-update-rc &>/dev/null
    else
      echo "⚠️  fzf install script not found at $FZF_INSTALL_SCRIPT"
    fi

    echo ""
    echo "💡 Terminal.app tips:"
    echo "   • Enable 'Use Option as Meta':"
    echo "     Terminal → Preferences → Profile → Keyboard → ✅ Use Option as Meta Key"
    echo "   • Customize window title:"
    echo "     Terminal → Preferences → Profile → Window → Title: Working Directory"
    echo "   • You may also want to disable the audible bell in Terminal → Settings → Advanced"
    read -n 1 -r -s -p $'Press any key once you’ve reviewed these suggestions...\n'
    echo ""

  elif [[ "$platform" == "linux" || "$platform" == "redhat" ]]; then
    if [ -d "$HOME/.fzf" ]; then
      echo "🔁 Updating existing ~/.fzf..."
      (cd "$HOME/.fzf" && git pull)
    else
      echo "⬇️  Cloning fzf..."
      git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    fi

    echo "⚙️  Running fzf install script for key bindings and completions..."
    ~/.fzf/install --key-bindings --completion --no-update-rc &>/dev/null
  fi
}

# Install Zsh plugins
install_zsh_plugins() {
  echo "🔌 Installing Zsh plugins..."
  mkdir -p ~/.zsh
  PLUGIN_NAMES=("zsh-syntax-highlighting" "zsh-autosuggestions" "pure")
  PLUGIN_URLS=(
    "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    "https://github.com/zsh-users/zsh-autosuggestions.git"
    "https://github.com/sindresorhus/pure.git"
  )
  if [[ "$platform" == "mac" ]]; then
    for plugin in "${PLUGIN_NAMES[@]}"; do
      if brew list "$plugin" &>/dev/null; then
        echo "✅ $plugin already installed via Homebrew"
      else
        echo "📦 Installing $plugin via Homebrew..."
        brew install "$plugin"
      fi
    done
  else
    for i in "${!PLUGIN_NAMES[@]}"; do
      plugin="${PLUGIN_NAMES[$i]}"
      url="${PLUGIN_URLS[$i]}"
      target="$HOME/.zsh/$plugin"
      if [[ -d "$target" ]]; then
        echo "✅ $plugin already installed"
      else
        echo "⬇️  Installing $plugin..."
        git clone "$url" "$target"
      fi
    done
  fi
}

# Install Snazzy theme (unified script)
install_snazzy_theme() {
    echo "🎨 Installing Snazzy terminal theme..."
    if ! bash "$DOTFILES_DIR/install_snazzy.sh"; then
        echo "⚠️  Warning: Snazzy theme installation failed or was skipped. You can try again by running install_snazzy."
    fi
}

# Install packages, zshplugins, and fzf
install_packages
install_zsh_plugins
install_snazzy_theme
install_fzf

# Symlink dotfiles
for filename in "${FILES_TO_LINK[@]}"; do
  target="$HOME/$filename"
  source="$DOTFILES_DIR/$filename"

  if [ ! -e "$source" ]; then
    echo "⚠️  Warning: $source not found. Skipping."
    continue
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    backup_file "$target"
  fi

  # Entries may be nested (e.g. .claude/settings.json); ln needs the parent to exist.
  mkdir -p "$(dirname "$target")"

  ln -sf "$source" "$target"
  echo "🔗 Linked $target → $source"
done

# Ensure Zsh completion cache directory exists
ZSH_CACHE_DIR="$HOME/.zsh/cache"
if [ ! -d "$ZSH_CACHE_DIR" ]; then
  echo "📂 Creating Zsh completion cache directory at $ZSH_CACHE_DIR"
  mkdir -p "$ZSH_CACHE_DIR"
else
  echo "✅ Zsh completion cache directory already exists"
fi

# Ensure ~/.gitconfig.local exists with user identity
if [[ ! -f "$HOME/.gitconfig.local" ]]; then
  echo "🧾 Setting up ~/.gitconfig.local (Git identity for this machine):"
  read -r -p "  Git user.name: " git_name
  read -r -p "  Git user.email: " git_email

  cat > "$HOME/.gitconfig.local" <<EOF
[user]
	name = $git_name
	email = $git_email
EOF

  echo "✅ ~/.gitconfig.local created."
fi

# Change shell to Zsh
ZSH_PATH="$(command -v zsh)"
if ! grep -q "$ZSH_PATH" /etc/shells; then
    echo "⚠️  $ZSH_PATH is not in /etc/shells. You may need to add it manually, otherwise chsh will fail silently."
fi

if [ "$SHELL" != "$ZSH_PATH" ]; then
  LOGIN_USER="$(whoami)"
  if ! grep -q "^$LOGIN_USER:" /etc/passwd; then
    echo "⚠️  Skipping chsh: user '$LOGIN_USER' not found in /etc/passwd. You may need to change shell manually."
  else
    echo "🌀 Changing default shell to Zsh ($ZSH_PATH) for user $LOGIN_USER..."
    chsh -s "$ZSH_PATH" "$LOGIN_USER"
  fi
fi

echo "✅ Dotfiles setup complete."
echo "📎 Restart your terminal or run: exec $ZSH_PATH"
