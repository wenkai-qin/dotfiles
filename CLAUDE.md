# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal dotfiles for macOS and Linux: shell config, Git config, terminal theme, and a backup of Claude Code's user-level config. Everything is Bash/Zsh — there is no build system, no test suite, and no package manifest.

## Commands

```bash
./install.sh              # full setup: packages, zsh plugins, theme, fzf, symlinks, chsh
./uninstall.sh            # remove symlinks (restoring backups), plugins, fzf cache
./install_snazzy.sh       # terminal theme only; --force reinstalls over an existing profile
./setup_ssh_linux.sh [true] [/path/to/id_rsa.pub]   # Ubuntu/Debian only; arg1 hardens sshd, arg2 installs a key
```

`install.sh` is idempotent and safe to re-run — every step checks for an existing install first.

**There is no linting, formatting, or test tooling in this repo**, and no CI. A `.trunk/` directory existed locally until it was removed in August 2026; it was never tracked by git (Trunk's "single player mode" excludes itself via `.git/info/exclude`), so it never applied to a clone. Do not reintroduce a lint config without the user asking.

For a one-off check of the shell scripts, `shellcheck install.sh uninstall.sh install_snazzy.sh setup_ssh_linux.sh` works if installed. Two things to know: `install.sh` deliberately word-splits `$CHECK_CMD` / `$INSTALL_CMD` (they hold multi-word commands like `sudo apt install -y`), so SC2086 there needs a `disable` comment rather than quoting; and shellcheck has no zsh support, so `.zshrc` — the most intricate file here — cannot be linted at all.

## Architecture

### Platform detection is duplicated, not shared

`install.sh`, `uninstall.sh`, and `install_snazzy.sh` each re-derive the platform inline. The first two resolve to `mac` / `linux` / `redhat` (RedHat is detected by `/etc/redhat-release` *before* the `uname` switch, since it also reports `Linux`); `install_snazzy.sh` only distinguishes `Darwin` / `Linux`. There is no shared library — a change to platform logic has to be made in each script.

The `mac` vs. `linux`/`redhat` split drives real behavior differences, not just package-manager names:

| | macOS | Linux / RedHat |
|---|---|---|
| zsh plugins | Homebrew formulae | `git clone` into `~/.zsh/<plugin>` |
| fzf | `brew install` + `$(brew --prefix)/opt/fzf/install` | `git clone` to `~/.fzf` + `~/.fzf/install` |
| Pure prompt | on `fpath` via Homebrew | `.zshrc` appends `~/.zsh/pure` to `fpath` explicitly |
| theme | Terminal.app plist + AppleScript | GNOME Terminal via gsettings/dconf + Gogh |

Anything added to `.zshrc` that resolves a path must handle both installation shapes.

### Symlink model

`install.sh` symlinks each entry of `FILES_TO_LINK` from the repo into `$HOME`, backing up any existing file as `<name>.bak.<epoch>`. `uninstall.sh` reverses this, but only removes a symlink if it actually points into this repo, then restores the newest matching backup.

**`FILES_TO_LINK` is declared separately in both scripts.** They are in sync as of August 2026 (the `.claude` entries were missing from `uninstall.sh` and survived uninstalls), and both carry a comment saying so. Adding a file means editing both arrays — nothing enforces it.

`backup_file` in `install.sh` must keep testing `-e`, matching its call site. If it narrows to `-f`/`-L`, a directory at the target gets no backup and `ln -sf` silently drops the link *inside* it — which is what happens the first time a directory (say `.claude/agents/`) is added to `FILES_TO_LINK`.

Machine-specific Git identity lives in `~/.gitconfig.local`, which `install.sh` prompts for and `.gitconfig` pulls in via `[include]`. It is never committed — keep name/email out of `.gitconfig`.

### The `.claude/` ignore inversion

`.gitignore_global` ignores `.claude/` and `CLAUDE.md` in *every* repo. This repo is the deliberate exception, because it is the backup of the user-level Claude Code config. `.gitignore` re-includes the directory, re-ignores its contents, then allowlists individual files:

```
!.claude/
.claude/*
!.claude/settings.json
!.claude/statusline-command.sh
```

This is default-deny on purpose — anything Claude Code later drops in `.claude/` (credentials, history, transcripts, caches) stays ignored, and `settings.local.json` in particular is *not* tracked. Publishing a new file under `.claude/` takes two deliberate edits: a `!` line in `.gitignore` **and** an entry in `FILES_TO_LINK` in both install/uninstall scripts.

`CLAUDE.md` is globally ignored for the same reason and carries its own `!CLAUDE.md` negation.

### `.zshrc` startup design

The file is optimized for startup latency and is order-sensitive:

- Line 2 is an interactive guard (`[[ $- != *i* ]] && return`) — nothing above it may assume an interactive shell.
- `compinit` is **lazy**. The original Tab widget is captured into `__ORIG_TAB_WIDGET`, `^I` is rebound to a `__init_comp` loader that runs `compinit` on first Tab press and then restores the real widget. Any code that rebinds Tab or registers completions must run *before* the `__ORIG_TAB_WIDGET` capture, or it will be clobbered when the loader restores the saved binding.
- The completion dump is cached at `~/.zsh/cache/zcompdump`; `install.sh` pre-creates that directory. The loader reads it with `compinit -C` (skips the rebuild check and `compaudit`) while it is under 24h old, and does a full rebuild past that so newly installed completions get picked up. The rebuild branch `touch`es the dump on purpose: `compinit` only rewrites it when its contents changed, so without the touch a still-valid dump keeps its old mtime and every later shell repeats the slow branch forever.
- Set `ZSH_TIME=1` or `ZSH_PROFILE=1` in the environment to print startup timing / a `zprof` report — use these to check that a `.zshrc` change did not regress startup.

### Claude Code status line

`.claude/statusline-command.sh` reads the status JSON on stdin and renders directory, git branch (with `*` when dirty), context-window remaining, and 5h/7d rate-limit usage, mirroring the Pure zsh prompt. It shells out with `--no-optional-locks` so it can never block on a git lock. Its header asks that changes go through the `statusline-setup` agent rather than hand-editing.

### Things that only break silently

Two classes of bug have shown up here more than once, both invisible without checking against the real tool:

- **Config keys that look active but aren't.** `.gitconfig` had `[ini]` (a typo for `[init]`) and `diff.ignoreWhitespace` (not a git key at all). Git stores unknown keys without complaint, so `git config --get` echoing a value proves nothing. Check names against `git help -c`.
- **Hardcoded indexes into someone else's list.** `install_snazzy.sh` piped the menu number `291` into Gogh to pick Snazzy; upstream added themes and 291 became Slate. It now selects by name. Prefer a name/slug over a position whenever the upstream list can grow.

`setup_ssh_linux.sh` installs the key *before* hardening and refuses to harden without one, on purpose — the reverse order can lock you out of a remote host. Keep that ordering. It also warns about `/etc/ssh/sshd_config.d/*.conf`, which can override the `sed`ed values since sshd takes the first value it sees.
