#!/bin/bash
# Claude Code status line.
#
# Mirrors the "Pure" zsh prompt's directory/git-branch content (sans the
# `>` glyph), plus context-window remaining % and Claude.ai rate-limit
# usage (5h / 7d). Managed by the statusline-setup agent -- ask it (or
# Claude generally) to make further changes rather than hand-editing.

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd="$PWD"

dir_name=$(basename "$cwd")

# --- git branch + dirty state (skip optional locks so this never blocks) ---
branch=""
dirty=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    if [ -z "$branch" ]; then
        branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
    fi
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        dirty="*"
    fi
fi

# --- context window remaining % ---
remaining=$(printf '%s' "$input" | jq -r '.context_window.remaining_percentage // empty')

# --- Claude.ai rate limits ---
five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# --- colors (plain ANSI, kept unbolded to read well when dimmed) ---
RESET=$'\033[0m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
GREEN=$'\033[32m'
GREY=$'\033[90m'

# Higher-is-worse metric (e.g. rate-limit usage).
color_for_used() {
    local p="$1"
    [ -z "$p" ] && { echo "$GREY"; return; }
    if awk -v p="$p" 'BEGIN{exit !(p>=80)}'; then echo "$RED"
    elif awk -v p="$p" 'BEGIN{exit !(p>=50)}'; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

# Lower-is-worse metric (e.g. context remaining).
color_for_remaining() {
    local p="$1"
    [ -z "$p" ] && { echo "$GREY"; return; }
    if awk -v p="$p" 'BEGIN{exit !(p<=20)}'; then echo "$RED"
    elif awk -v p="$p" 'BEGIN{exit !(p<=50)}'; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

out="${BLUE}${dir_name}${RESET}"

if [ -n "$branch" ]; then
    branch_color="$MAGENTA"
    [ -n "$dirty" ] && branch_color="$YELLOW"
    out="${out}${GREY} on ${RESET}${branch_color}${branch}${dirty}${RESET}"
fi

if [ -n "$remaining" ]; then
    rc=$(color_for_remaining "$remaining")
    out="${out}${GREY} | ${RESET}${rc}ctx:$(printf '%.0f' "$remaining")%${RESET}"
fi

if [ -n "$five" ] || [ -n "$week" ]; then
    out="${out}${GREY} | ${RESET}"
    if [ -n "$five" ]; then
        c=$(color_for_used "$five")
        out="${out}${c}5h:$(printf '%.0f' "$five")%${RESET}"
        [ -n "$week" ] && out="${out} "
    fi
    if [ -n "$week" ]; then
        c=$(color_for_used "$week")
        out="${out}${c}7d:$(printf '%.0f' "$week")%${RESET}"
    fi
fi

printf '%s\n' "$out"
