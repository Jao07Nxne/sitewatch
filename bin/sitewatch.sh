#!/usr/bin/env bash
# Project: SiteWatch - ระบบเฝ้าระวังเว็บไซต์และบริการ
# Member Name 1: 66050027 นายกันตวัฒน์ แช่มช้อย
# Member Name 2: 66050160 นายเตชสิทธิ์ วาณิชภัทรกุล
# Member Name 3: 66050193 นายธัชชัย ลิ่มพิทักษ์

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
REAL_SOURCE="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SOURCE")" && pwd)"

# ------------------------------------------------------------------------------
# ตรวจสอบหาตำแหน่ง Config 
# ------------------------------------------------------------------------------
if [[ -r "/etc/sitewatch/sitewatch.conf" ]]; then
    DEFAULT_CONFIG="/etc/sitewatch/sitewatch.conf"
elif [[ -r "${SCRIPT_DIR}/../config/sitewatch.conf" ]]; then
    DEFAULT_CONFIG="${SCRIPT_DIR}/../config/sitewatch.conf"
elif [[ -r "/opt/sitewatch/config/sitewatch.conf" ]]; then
    DEFAULT_CONFIG="/opt/sitewatch/config/sitewatch.conf"
else
    DEFAULT_CONFIG="${SCRIPT_DIR}/../config/sitewatch.conf"
fi

CONFIG_FILE="$DEFAULT_CONFIG"
LOG_FILE="/var/log/sitewatch/sitewatch.log"
VERBOSE=0
DRY_RUN=0

# ------------------------------------------------------------------------------
# Logging Functions 
# ------------------------------------------------------------------------------
log() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%F %T')"

    local c_reset="" c_color=""
    if [[ -t 2 ]]; then
        c_reset='\033[0m'
        case "$level" in
            INFO)  c_color='\033[1;32m' ;; # สีเขียว
            WARN)  c_color='\033[1;33m' ;; # สีเหลือง
            ERROR) c_color='\033[1;31m' ;; # สีแดง
            DEBUG) c_color='\033[0;36m' ;; # สีฟ้าอมเขียว
            *)     c_color='\033[1;37m' ;;
        esac
    fi

    # ข้อความสำหรับแสดงผลหน้าจอ
    local screen_msg="${timestamp} [${c_color}${level}${c_reset}] $*"
    # ข้อความสำหรับลงไฟล์ log
    local plain_msg="${timestamp} [${level}] $*"

    echo -e "$screen_msg" >&2

    if [[ -d "$(dirname "$LOG_FILE")" && -w "$(dirname "$LOG_FILE")" ]]; then
        echo "$plain_msg" >> "$LOG_FILE"
    fi
}

debug() {
    if (( VERBOSE )); then
        log DEBUG "$*"
    fi
}

run() {
    if (( DRY_RUN )); then
        log INFO "[dry-run] $*"
    else
        "$@"
    fi
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-c config] [-v] [-n] [-h] [--uninstall]

Options:
  -c FILE        ระบุไฟล์ config (ค่าเริ่มต้น: /etc/sitewatch/sitewatch.conf)
  -v             แสดงรายละเอียดการทำงาน (Verbose)
  -n             โหมด dry-run (ทดสอบโดยไม่บันทึกข้อมูล)
  -h, --help     แสดงวิธีใช้งาน
  --uninstall    ถอนการติดตั้ง SiteWatch ออกจากระบบโดยสมบูรณ์
EOF
}

check_deps() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log ERROR "ไม่พบคำสั่ง: $cmd ในระบบ"
            exit 1
        fi
    done
}

# ------------------------------------------------------------------------------
# Callback Receiver
# ------------------------------------------------------------------------------
process_probe_result() {
    local target="$1"
    local type="$2"
    local status="$3"
    local latency="$4"
    local detail="$5"
    local timestamp
    timestamp="$(date '+%F %T')"

    debug "  └─ ผลการตรวจ: $status (${latency}ms, $detail)"

    if declare -f handle_state_alert >/dev/null; then
        handle_state_alert "$target" "$status" "$DRY_RUN"
    fi

    if declare -f record_metric >/dev/null; then
        record_metric "$timestamp" "$target" "$type" "$status" "$latency" "$detail" "$DRY_RUN"
    fi
}

print_banner() {
    if [[ ! -t 1 ]]; then
        return 0
    fi

    cat << "EOF"

[38;5;51m ███████╗██╗████████╗███████╗██╗    ██╗ █████╗ ████████╗ ██████╗██╗  ██╗
[38;5;45m ██╔════╝██║╚══██╔══╝██╔════╝██║    ██║██╔══██╗╚══██╔══╝██╔════╝██║  ██║
[38;5;45m ███████╗██║   ██║   █████╗  ██║ █╗ ██║███████║   ██║   ██║     ███████║
[38;5;39m ╚════██║██║   ██║   ██╔══╝  ██║███╗██║██╔══██║   ██║   ██║     ██╔══██║
[38;5;39m ███████║██║   ██║   ███████╗╚███╔███╔╝██║  ██║   ██║   ╚██████╗██║  ██║
[38;5;27m ╚══════╝╚═╝   ╚═╝   ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝
[38;5;244m                -- Linux Automation Project --[0m
EOF
    echo ""
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    # ตรวจสอบ Flag พิเศษ เช่น --uninstall หรือ --help
    for arg in "$@"; do
        case "$arg" in
            --uninstall|-u)
                if [[ "${EUID}" -ne 0 ]]; then
                    echo "[INFO] Sudo privileges required to uninstall SiteWatch."
                    exec sudo "$REAL_SOURCE" "$@"
                fi

                local uninstaller=""
                if [[ -x "/opt/sitewatch/uninstall.sh" ]]; then
                    uninstaller="/opt/sitewatch/uninstall.sh"
                elif [[ -x "${SCRIPT_DIR}/../uninstall.sh" ]]; then
                    uninstaller="${SCRIPT_DIR}/../uninstall.sh"
                elif [[ -x "${SCRIPT_DIR}/uninstall.sh" ]]; then
                    uninstaller="${SCRIPT_DIR}/uninstall.sh"
                fi

                if [[ -n "$uninstaller" ]]; then
                    local remaining_args=()
                    for a in "$@"; do
                        if [[ "$a" != "--uninstall" && "$a" != "-u" ]]; then
                            remaining_args+=("$a")
                        fi
                    done
                    exec "$uninstaller" "${remaining_args[@]+"${remaining_args[@]}"}"
                else
                    echo "[ERROR] ไม่พบไฟล์สคริปต์ถอนการติดตั้ง (uninstall.sh)" >&2
                    exit 1
                fi
                ;;
            --help)
                usage
                exit 0
                ;;
        esac
    done

    print_banner

    while getopts ":c:vnh" opt; do
        case $opt in
            c) CONFIG_FILE="$OPTARG" ;;
            v) VERBOSE=1 ;;
            n) DRY_RUN=1 ;;
            h) usage; exit 0 ;;
            *) usage; exit 2 ;;
        esac
    done

    # ตรวจสอบความถูกต้องของไฟล์ Config
    if [[ ! -r "$CONFIG_FILE" ]]; then
        echo "อ่าน config ไม่ได้ หรือไม่พบไฟล์: $CONFIG_FILE" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    # โหลดโมดูล
    if [[ -f "${SCRIPT_DIR}/prober.sh" ]]; then
        # shellcheck source=/dev/null
        source "${SCRIPT_DIR}/prober.sh"
    else
        log ERROR "ไม่พบไฟล์โมดูล ${SCRIPT_DIR}/prober.sh"
        exit 1
    fi

    # โหลดโมดูล metric.sh และ state_alert.sh 
    # shellcheck source=/dev/null
    [[ -f "${SCRIPT_DIR}/metric.sh" ]] && source "${SCRIPT_DIR}/metric.sh"
    # shellcheck source=/dev/null
    [[ -f "${SCRIPT_DIR}/state_alert.sh" ]] && source "${SCRIPT_DIR}/state_alert.sh"

    # ตรวจสอบเครื่องมือพื้นฐาน
    check_deps date awk grep curl nc
    prober_check_deps

    log INFO "SiteWatch เริ่มต้นการตรวจสอบเป้าหมาย..."
    debug "ใช้ไฟล์ config: $CONFIG_FILE"

    run_probes

    if declare -f display_uptime_summary >/dev/null; then
        display_uptime_summary
    fi

    log INFO "การตรวจสอบเสร็จสิ้นสมบูรณ์"
}

main "$@"