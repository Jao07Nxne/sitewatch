#!/usr/bin/env bash
set -euo pipefail

# Check root privilege
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Please run with sudo: sudo ./uninstall.sh" >&2
    exit 1
fi

echo "Uninstalling SiteWatch..."

# 1. Stop and disable systemd timer & service
systemctl stop sitewatch.timer 2>/dev/null || true
systemctl disable sitewatch.timer 2>/dev/null || true
systemctl stop sitewatch.service 2>/dev/null || true

# 2. Remove systemd files
rm -f /etc/systemd/system/sitewatch.service /etc/systemd/system/sitewatch.timer
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# 3. Remove program files and data
rm -f /usr/local/bin/sitewatch
rm -rf /opt/sitewatch
rm -rf /etc/sitewatch /var/lib/sitewatch /var/log/sitewatch

echo "SiteWatch uninstalled successfully."
