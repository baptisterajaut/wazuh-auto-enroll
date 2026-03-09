#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: $0 [-k <keyfile>] [-n <agent-name>]"
    echo "  -k  Path to .key profile file (default: config.key in script directory)"
    echo "  -n  Custom agent name (default: hostname)"
    exit 1
}

KEY_FILE=""
AGENT_NAME="$(hostname)"

while getopts "k:n:h" opt; do
    case $opt in
        k) KEY_FILE="$OPTARG" ;;
        n) AGENT_NAME="$OPTARG" ;;
        *) usage ;;
    esac
done

# Default: config.key next to the script
if [[ -z "$KEY_FILE" ]]; then
    KEY_FILE="$SCRIPT_DIR/config.key"
fi
[[ ! -f "$KEY_FILE" ]] && echo "Key file not found: $KEY_FILE" && exit 1

# --- Parse key file ---
WAZUH_MANAGER=$(grep '^manager=' "$KEY_FILE" | cut -d= -f2)
WAZUH_REGISTRATION_PASSWORD=$(grep '^password=' "$KEY_FILE" | cut -d= -f2)
WAZUH_GROUP=$(grep '^group=' "$KEY_FILE" | cut -d= -f2)

[[ -z "$WAZUH_MANAGER" ]] && echo "Missing 'manager' in key file" && exit 1
[[ -z "$WAZUH_REGISTRATION_PASSWORD" ]] && echo "Missing 'password' in key file" && exit 1
[[ -z "$WAZUH_GROUP" ]] && echo "Missing 'group' in key file" && exit 1

echo "Manager: $WAZUH_MANAGER | Group: $WAZUH_GROUP | Agent name: $AGENT_NAME"

# --- Needs root ---
if [[ $EUID -ne 0 ]]; then
    echo "Run as root (or sudo)."
    exit 1
fi

# --- Abort if manager is already installed ---
if dpkg -l wazuh-manager 2>/dev/null | grep -q '^ii' || rpm -q wazuh-manager &>/dev/null || pacman -Q wazuh-manager &>/dev/null; then
    echo "ERROR: wazuh-manager is installed on this machine. The manager already monitors itself."
    exit 1
fi

# --- Detect package manager ---
if command -v apt-get &>/dev/null; then
    PKG="apt"
elif command -v yum &>/dev/null; then
    PKG="yum"
elif command -v pacman &>/dev/null; then
    PKG="pacman"
else
    PKG="unknown"
fi

# --- Install (skip if already installed) ---
export WAZUH_MANAGER WAZUH_REGISTRATION_PASSWORD

ALREADY_INSTALLED=false
if [[ -x /var/ossec/bin/agent-auth ]]; then
    ALREADY_INSTALLED=true
elif case $PKG in
    apt)    dpkg -l wazuh-agent 2>/dev/null | grep -q '^ii' ;;
    yum)    rpm -q wazuh-agent &>/dev/null ;;
    pacman) pacman -Q wazuh-agent &>/dev/null ;;
    *)      false ;;
esac; then
    ALREADY_INSTALLED=true
fi

if $ALREADY_INSTALLED; then
    echo "wazuh-agent already installed, skipping install."
elif [[ "$PKG" == "unknown" ]]; then
    echo "ERROR: No supported package manager (apt/yum/pacman) and wazuh-agent is not installed."
    echo "Install wazuh-agent manually, then re-run this script to enroll."
    exit 1
else
    case $PKG in
        apt)
            apt-get install -y gnupg apt-transport-https
            curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
                gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import 2>/dev/null
            chmod 644 /usr/share/keyrings/wazuh.gpg
            echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
                > /etc/apt/sources.list.d/wazuh.list
            apt-get update
            apt-get install -y wazuh-agent
            ;;
        yum)
            rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
            cat > /etc/yum.repos.d/wazuh.repo << 'EOF'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
            yum install -y wazuh-agent
            ;;
        pacman)
            SUDO_USER_NAME="${SUDO_USER:-}"
            if [[ -z "$SUDO_USER_NAME" ]]; then
                echo "On Arch, run with sudo (not as direct root) so the AUR helper can build as your user."
                exit 1
            fi
            AUR_HELPER=""
            for helper in pikaur yay; do
                AUR_HELPER=$(sudo -u "$SUDO_USER_NAME" bash -lc "which $helper" 2>/dev/null || true)
                [[ -n "$AUR_HELPER" ]] && break
            done
            if [[ -z "$AUR_HELPER" ]]; then
                echo "No AUR helper found (pikaur or yay) for user $SUDO_USER_NAME."
                exit 1
            fi
            sudo -u "$SUDO_USER_NAME" "$AUR_HELPER" -S --noconfirm wazuh-agent
            ;;
    esac
fi

# --- Configure ---
OSSEC_CONF="/var/ossec/etc/ossec.conf"
if [[ ! -f "$OSSEC_CONF" ]]; then
    echo "ERROR: $OSSEC_CONF not found after install."
    exit 1
fi

# Set manager address
if grep -q '<address>MANAGER_IP</address>' "$OSSEC_CONF" 2>/dev/null; then
    sed -i "s|<address>MANAGER_IP</address>|<address>${WAZUH_MANAGER}</address>|" "$OSSEC_CONF"
fi
if ! grep -q "<address>${WAZUH_MANAGER}</address>" "$OSSEC_CONF"; then
    sed -i "s|<address>[^<]*</address>|<address>${WAZUH_MANAGER}</address>|" "$OSSEC_CONF"
fi

# Write enrollment password
echo "$WAZUH_REGISTRATION_PASSWORD" > /var/ossec/etc/authd.pass
chmod 640 /var/ossec/etc/authd.pass

# --- Enroll if not already enrolled ---
if [[ ! -s /var/ossec/etc/client.keys ]]; then
    echo "Enrolling agent '$AGENT_NAME' in group '$WAZUH_GROUP'..."
    /var/ossec/bin/agent-auth -m "$WAZUH_MANAGER" -P "$WAZUH_REGISTRATION_PASSWORD" -A "$AGENT_NAME" -G "$WAZUH_GROUP"
fi

# --- Start ---
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl restart wazuh-agent

echo ""
echo "Wazuh agent '$AGENT_NAME' installed and enrolled to $WAZUH_MANAGER (group: $WAZUH_GROUP)"
systemctl status wazuh-agent --no-pager -l | head -5
