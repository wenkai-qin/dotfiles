#!/bin/bash
set -e

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID,,}"  # normalize to lowercase
else
    echo "[x] Cannot detect OS. /etc/os-release not found."
    exit 1
fi

# Allow only Ubuntu or Debian
if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    echo "[x] Unsupported OS: $OS_ID. This script supports only Ubuntu or Debian."
    exit 1
fi

echo "[✓] Detected supported OS: $PRETTY_NAME"

echo "[+] Updating system..."
sudo apt update

echo "[+] Installing OpenSSH Server..."
sudo apt install -y openssh-server

echo "[+] Enabling and starting ssh service..."
sudo systemctl enable ssh
sudo systemctl start ssh

echo "[+] Checking firewall (ufw)..."
if command -v ufw >/dev/null; then
    if sudo ufw status | grep -q "Status: active"; then
        echo "[+] UFW is active. Allowing SSH..."
        sudo ufw allow ssh
        sudo ufw reload
    else
        echo "[!] UFW is not active. Skipping firewall configuration."
    fi
else
    echo "[!] UFW is not installed. Skipping firewall configuration."
fi

HARDEN=${1:-false}
PUBKEY_PATH="${2:-}"
USER_HOME=$(eval echo "~$USER")
AUTH_KEYS="$USER_HOME/.ssh/authorized_keys"

# Key setup runs BEFORE hardening, and its inputs are validated before anything
# touches sshd. Hardening disables password auth, so a failure between the two
# would leave a remote host with no usable way in.
if [ -n "$PUBKEY_PATH" ] && [ ! -f "$PUBKEY_PATH" ]; then
    echo "[x] Public key file not found: $PUBKEY_PATH"
    echo "[x] Aborting before any sshd changes."
    exit 1
fi

# Optional SSH key setup
if [ -n "$PUBKEY_PATH" ]; then
    echo "[+] Setting up SSH key authentication..."
    mkdir -p "$USER_HOME/.ssh"
    cat "$PUBKEY_PATH" >> "$AUTH_KEYS"
    chmod 700 "$USER_HOME/.ssh"
    chmod 600 "$AUTH_KEYS"
    chown -R "$USER":"$USER" "$USER_HOME/.ssh"
    echo "[✓] SSH key added for user $USER"
fi

# Optional hardening
if [ "$HARDEN" = "true" ]; then
    # Refuse to disable password auth with no key to fall back on -- that
    # combination is unrecoverable on a remote machine.
    if [ ! -s "$AUTH_KEYS" ]; then
        echo "[x] Refusing to harden: $AUTH_KEYS is missing or empty."
        echo "[x] Pass a public key as the second argument, e.g.:"
        echo "    $0 true ~/.ssh/id_ed25519.pub"
        exit 1
    fi

    echo "[+] Hardening SSH configuration..."
    sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

    # Ubuntu 22.10+ ships /etc/ssh/sshd_config.d/*.conf, and cloud images drop
    # 50-cloud-init.conf with "PasswordAuthentication yes". sshd takes the FIRST
    # value it sees, so an Include can silently override the edits above.
    OVERRIDES=$(grep -rilE '^\s*#?\s*(PasswordAuthentication|PermitRootLogin)' \
        /etc/ssh/sshd_config.d/ 2>/dev/null || true)
    if [ -n "$OVERRIDES" ]; then
        echo "[!] These drop-in files also set PasswordAuthentication/PermitRootLogin"
        echo "[!] and may take precedence over /etc/ssh/sshd_config:"
        echo "$OVERRIDES" | sed 's/^/      /'
        echo "[!] Edit them too, or the hardening below will not fully apply."
    fi

    sudo systemctl reload ssh

    # Report what sshd actually resolved, not what we intended to set.
    echo "[+] Effective sshd settings after reload:"
    sudo sshd -T 2>/dev/null \
        | grep -iE '^(passwordauthentication|permitrootlogin)' \
        | sed 's/^/      /' \
        || echo "      (could not run 'sshd -T' to verify)"
fi

echo "[✓] SSH setup complete."
echo "Your IP address is: $(hostname -I | awk '{print $1}')"
