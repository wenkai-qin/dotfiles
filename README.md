# Dotfiles Setup

This repository contains Wenkai's personal dotfiles and helper scripts for configuring
Zsh, Git, and terminal themes on macOS and Linux.

The main entry point is **`install.sh`** which detects your operating system and performs
these tasks:

1. Installs required packages (`zsh`, `git`, `curl` and Homebrew on macOS).
2. Installs Zsh plugins (pure prompt, zsh-autosuggestions and zsh-syntax-highlighting).
3. Applies the "Snazzy" terminal theme using `install_snazzy.sh`.
4. Installs [fzf](https://github.com/junegunn/fzf) with key bindings and completion.
5. Symlinks dotfiles from this repo to your home directory (`.zshrc`, `.gitconfig`,
   `.gitignore_global`, and Claude Code's `settings.json` / `statusline-command.sh`).
   Existing files are backed up with a timestamp suffix.
6. Creates `~/.gitconfig.local` for your personal Git name and email if it does not exist.
7. Changes your default shell to Zsh.

To undo the changes run `./uninstall.sh`, which removes the symlinks (restoring the
newest backup of each), the Zsh plugins and fzf. The terminal theme is left in place —
remove that profile yourself from your terminal's settings.

Additional scripts include:

- `install_snazzy.sh` – Cross-platform installer for the Snazzy terminal theme
  (Terminal.app on macOS, GNOME Terminal via Gogh on Linux). Pass `--force` to
  reinstall over an existing profile.
- `setup_ssh_linux.sh` – Installs and optionally hardens OpenSSH on Ubuntu/Debian.
  Pass `true` as the first argument to disable root login and password auth, and a
  public key path as the second. Hardening requires a key — the script refuses to
  disable password auth with no key installed, since that can lock you out.

## Usage

Clone the repository and execute the install script:

```bash
./install.sh
```

The script will print progress messages and prompt for your Git identity when
creating `~/.gitconfig.local`. After completion restart your terminal or run
`exec $(which zsh)` to start using the new configuration.
