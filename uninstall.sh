#!/usr/bin/env bash
set -euo pipefail

# Check root privilege
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Please run with sudo: sudo ./uninstall.sh" >&2
    exit 1
fi

PURGE_DEPS=0
for arg in "$@"; do
    case "$arg" in
        --purge-deps|-p)
            PURGE_DEPS=1
            ;;
        -h|--help)
            echo "Usage: sudo ./uninstall.sh [--purge-deps]"
            echo "  --purge-deps, -p    Remove dependencies installed via apt (netcat-openbsd, dnsutils)"
            exit 0
            ;;
    esac
done

echo "Uninstalling SiteWatch..."

# 1. Terminate any running sitewatch processes
pkill -f "/opt/sitewatch/bin" 2>/dev/null || true
pkill -f "sitewatch.sh" 2>/dev/null || true

# 2. Stop and disable systemd timer & service
systemctl stop sitewatch.timer 2>/dev/null || true
systemctl disable --now sitewatch.timer 2>/dev/null || true
systemctl stop sitewatch.service 2>/dev/null || true
systemctl disable --now sitewatch.service 2>/dev/null || true

# 3. Remove systemd files, symlinks, and drop-in configurations
rm -f /etc/systemd/system/sitewatch.service /etc/systemd/system/sitewatch.timer
rm -f /etc/systemd/system/timers.target.wants/sitewatch.timer 2>/dev/null || true
rm -f /etc/systemd/system/multi-user.target.wants/sitewatch.service 2>/dev/null || true
rm -rf /etc/systemd/system/sitewatch.service.wants /etc/systemd/system/sitewatch.timer.wants 2>/dev/null || true
rm -rf /etc/systemd/system/sitewatch.service.d /etc/systemd/system/sitewatch.timer.d 2>/dev/null || true

systemctl daemon-reload
systemctl reset-failed sitewatch.timer sitewatch.service 2>/dev/null || true
systemctl reset-failed 2>/dev/null || true

# 4. Remove program files, symlinks, configuration, and data
rm -f /usr/local/bin/sitewatch
rm -rf /opt/sitewatch
rm -rf /etc/sitewatch
rm -rf /var/lib/sitewatch
rm -rf /var/log/sitewatch
rm -f /var/log/sitewatch*.log /var/log/sitewatch*.csv 2>/dev/null || true

# 5. Remove temporary and runtime files
rm -rf /tmp/sitewatch* 2>/dev/null || true

# 6. Purge dependencies if requested
if [[ "$PURGE_DEPS" -eq 1 ]]; then
    echo "Purging dependencies..."
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get remove --purge -y netcat-openbsd dnsutils 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    fi
fi

echo "SiteWatch uninstalled and cleaned up successfully."
