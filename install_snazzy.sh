#!/usr/bin/env bash

set -e

FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
    echo "🔁 Force mode enabled — will reinstall Snazzy theme."
fi

PLATFORM="$(uname)"

case "$PLATFORM" in
Darwin)
    echo "🧠 macOS detected — configuring Terminal.app..."

    THEME_NAME="Snazzy"
    PLIST="$HOME/Library/Preferences/com.apple.Terminal.plist"

    if /usr/libexec/PlistBuddy -c "Print 'Window Settings':$THEME_NAME" "$PLIST" &>/dev/null && [[ "$FORCE" == false ]]; then
        echo "✅ Terminal profile '$THEME_NAME' already exists. Skipping installation."
        exit 0
    fi

    THEME_URL="https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/terminal/Snazzy.terminal"
    TMP_DIR=$(mktemp -d)
    THEME_PATH="$TMP_DIR/Snazzy.terminal"
    echo "🎨 Downloading Snazzy theme for Terminal.app..."
    curl -fsSL -o "$THEME_PATH" "$THEME_URL"

    echo "📂 Importing theme..."
    open "$THEME_PATH"
    sleep 2

    echo "📌 Applying theme to all windows..."
    osascript <<EOF
    if application "Terminal" is not running then
        tell application "Terminal" to activate
    end if
    tell application "Terminal"
        set default settings to settings set "$THEME_NAME"
        set startup settings to settings set "$THEME_NAME"
        repeat with w in windows
            repeat with t in tabs of w
                set current settings of t to settings set "$THEME_NAME"
            end repeat
        end repeat
    end tell
EOF

    echo "🖋️ Setting font to Menlo 12pt..."
    osascript <<EOF
    tell application "Terminal"
        set font name of settings set "$THEME_NAME" to "Menlo-Regular"
        set font size of settings set "$THEME_NAME" to 12
    end tell
EOF

    rm -rf "$TMP_DIR"
    echo "🎉 Snazzy theme applied to Terminal.app!"

    ;;

Linux)
    echo "🧠 Linux detected — configuring GNOME Terminal..."

    if [[ -z "$DISPLAY" ]] || ! gsettings list-schemas &>/dev/null || [[ "$XDG_CURRENT_DESKTOP" != *GNOME* && "$XDG_SESSION_DESKTOP" != *gnome* ]]; then
        echo "❌ Snazzy theme install requires an active GNOME session with access to gsettings."
        echo "💡 Make sure you're running this from GNOME Terminal or a VNC/X11 session on the desktop, not SSH."
        exit 0
    fi

    echo "🔧 Installing dependencies..."
    if command -v apt &>/dev/null; then
        sudo apt update
        sudo apt install -y dconf-cli uuid-runtime wget curl
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y dconf uuid wget curl
    elif command -v yum &>/dev/null; then
        sudo yum install -y dconf uuid wget curl
    else
        echo "❌ Unsupported package manager. Install dconf, uuid, wget, and curl manually."
        exit 1
    fi

    # Create a temporary profile if no profiles exist to avoid gsettings errors
    PROFILE_LIST=$(gsettings get org.gnome.Terminal.ProfilesList list | tr -d "[],'")
    if [[ -z "$PROFILE_LIST" ]]; then
        echo "⚠️  No existing terminal profiles found. Creating temporary profile..."
        TMP_UUID=$(uuidgen)
        gsettings set org.gnome.Terminal.ProfilesList list "['$TMP_UUID']"
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TMP_UUID/" visible-name 'tmp'
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TMP_UUID/" use-system-font true
        PROFILE_LIST="$TMP_UUID"
        TMP_PROFILE_CREATED=true
    fi

    PROFILE_LIST=$(gsettings get org.gnome.Terminal.ProfilesList list | tr -d "[],'")
    for PROFILE_ID in $PROFILE_LIST; do
        NAME=$(gsettings get "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/" visible-name | tr -d "'")
        if [[ "$NAME" == "Snazzy" ]]; then
            EXISTING_UUID="$PROFILE_ID"
            break
        fi
    done

    if [[ -n "$EXISTING_UUID" && "$FORCE" == false ]]; then
        echo "✅ Snazzy profile already exists (UUID: $EXISTING_UUID). Skipping installation."
        gsettings set org.gnome.Terminal.ProfilesList default "$EXISTING_UUID"
        exit 0
    fi

    if [[ -n "$EXISTING_UUID" && "$FORCE" == true ]]; then
        echo "🔁 Reinstalling Snazzy theme after forced removal..."
        dconf reset -f "/org/gnome/terminal/legacy/profiles:/:$EXISTING_UUID/"
        UPDATED_LIST=$(echo "$PROFILE_LIST" | tr ' ' '\n' | grep -v "^$EXISTING_UUID$" | paste -sd, -)
        gsettings set org.gnome.Terminal.ProfilesList list "[$UPDATED_LIST]"
    fi

    echo "🎨 Installing Snazzy via Gogh..."
    # Select by name, not by menu index. This used to pipe "291" into Gogh's
    # interactive prompt, but the theme list is ordered and upstream additions
    # shift it -- 291 is now Slate, and Snazzy has moved to 293. Gogh accepts a
    # theme name/slug as an argument, which also skips the interactive prompt.
    #
    # $0 must be a placeholder: `bash -c CMD name arg` assigns name to $0.
    # TERMINAL is set explicitly because Gogh otherwise walks the process tree
    # with ps to guess it, which is unreliable under `bash -c`; the enclosing
    # branch has already confirmed a GNOME session.
    GOGH_URL="https://raw.githubusercontent.com/Mayccoll/Gogh/master/gogh.sh"
    if ! TERMINAL=gnome-terminal bash -c "$(wget -qO- "$GOGH_URL")" gogh snazzy; then
        echo "❌ Gogh failed to install the Snazzy theme."
        exit 1
    fi
    sleep 1

    PROFILE_LIST=$(gsettings get org.gnome.Terminal.ProfilesList list | tr -d "[],'")
    for PROFILE_ID in $PROFILE_LIST; do
        NAME=$(gsettings get "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/" visible-name)
        if [[ $NAME == *"Snazzy"* ]]; then
            SNAZZY_UUID=$PROFILE_ID
            break
        fi
    done

    if [ -z "$SNAZZY_UUID" ]; then
        echo "❌ Snazzy profile not found after install."
        exit 1
    fi

    echo "📌 Setting Snazzy as the default profile..."
    gsettings set org.gnome.Terminal.ProfilesList default "$SNAZZY_UUID"

    # Remove temporary profile if it was created
    if [[ "$TMP_PROFILE_CREATED" == true ]]; then
        echo "🧹 Removing temporary profile..."
        dconf reset -f "/org/gnome/terminal/legacy/profiles:/:$TMP_UUID/"
        PROFILE_LIST=$(gsettings get org.gnome.Terminal.ProfilesList list | tr -d "[],'")
        UPDATED_LIST=$(echo "$PROFILE_LIST" | tr ' ' '\n' | grep -v "^$TMP_UUID$" | paste -sd, -)
        gsettings set org.gnome.Terminal.ProfilesList list "[$UPDATED_LIST]"
    fi

    echo "🖋️ Setting font to Monospace 12..."
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$SNAZZY_UUID/" font 'Monospace 12'
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$SNAZZY_UUID/" use-system-font false

    echo "🎉 Snazzy theme applied to GNOME Terminal!"
    ;;

*)
    echo "❌ Unsupported platform: $PLATFORM"
    exit 1
    ;;
esac
