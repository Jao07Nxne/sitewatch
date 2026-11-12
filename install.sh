#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check root privilege
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Please run with sudo: sudo ./install.sh" >&2
    exit 1
fi

echo "Installing SiteWatch..."

# 1. Install and check dependencies
echo "Checking and installing dependencies..."
if command -v apt-get >/dev/null 2>&1; then
    echo "Updating apt cache and installing required packages (curl, netcat-openbsd, gawk, dnsutils)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl netcat-openbsd gawk dnsutils
elif command -v dnf >/dev/null 2>&1; then
    echo "Installing required packages with dnf..."
    dnf install -y curl nc gawk bind-utils
elif command -v yum >/dev/null 2>&1; then
    echo "Installing required packages with yum..."
    yum install -y curl nc gawk bind-utils
fi

for cmd in curl nc awk date systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Missing dependency: $cmd" >&2
        exit 1
    fi
done

# 2. Create directories
mkdir -p /opt/sitewatch/bin /opt/sitewatch/config /etc/sitewatch /var/log/sitewatch /var/lib/sitewatch
chmod 755 /opt/sitewatch /opt/sitewatch/bin /opt/sitewatch/config /etc/sitewatch /var/log/sitewatch /var/lib/sitewatch

# 3. Copy program files and configuration
cp -f "${SCRIPT_DIR}/bin/"*.sh /opt/sitewatch/bin/
chmod 755 /opt/sitewatch/bin/*.sh
cp -f "${SCRIPT_DIR}/config/sitewatch.conf" /opt/sitewatch/config/sitewatch.conf

if [[ ! -f /etc/sitewatch/sitewatch.conf ]]; then
    cp -f "${SCRIPT_DIR}/config/sitewatch.conf" /etc/sitewatch/sitewatch.conf
    chmod 644 /etc/sitewatch/sitewatch.conf
fi

ln -sf /opt/sitewatch/bin/sitewatch.sh /usr/local/bin/sitewatch

# 4. Install and enable systemd timer
cp -f "${SCRIPT_DIR}/systemd/sitewatch.service" /etc/systemd/system/
cp -f "${SCRIPT_DIR}/systemd/sitewatch.timer" /etc/systemd/system/
chmod 644 /etc/systemd/system/sitewatch.service /etc/systemd/system/sitewatch.timer

systemctl daemon-reload
systemctl enable --now sitewatch.timer

echo "SiteWatch installed successfully."
