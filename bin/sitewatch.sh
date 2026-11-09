#!/usr/bin/env bash
# ==============================================================================
# Project: SiteWatch - ระบบเฝ้าระวังเว็บไซต์และบริการ
# ==============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ค่าเริ่มต้นของตัวแปรระบบ
CONFIG_FILE="${SCRIPT_DIR}/../config/sitewatch.conf"
LOG_FILE="/var/log/sitewatch/sitewatch.log"
VERBOSE=0
DRY_RUN=0

# ------------------------------------------------------------------------------
# Logging Functions (ตาม Template อาจารย์)
# ------------------------------------------------------------------------------
log() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%F %T')"
    # แสดงผลออก stderr และบันทึกลงไฟล์ log (ถ้ามีสิทธิ์เขียนไฟล์)
    if [[ -d "$(dirname "$LOG_FILE")" && -w "$(dirname "$LOG_FILE")" ]]; then
        echo "${timestamp} [${level}] $*" | tee -a "$LOG_FILE" >&2
    else
        echo "${timestamp} [${level}] $*" >&2
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
Usage: $SCRIPT_NAME [-c config] [-v] [-n] [-h]

Option:
  -c FILE   ระบุไฟล์ config (ค่าเริ่มต้น: ../config/sitewatch.conf)
  -v        แสดงรายละเอียดการทำงาน (Verbose mode)
  -n        dry-run (แสดงสิ่งที่จะทำ แต่ไม่เขียนไฟล์หรือแตะต้องระบบจริง)
  -h        แสดงวิธีใช้งาน
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
# Callback Receiver (ตัวรับผลลัพธ์จาก prober.sh เพื่อส่งต่อให้ metric & alert)
# ------------------------------------------------------------------------------
process_probe_result() {
    local target="$1"
    local type="$2"
    local status="$3"
    local latency="$4"
    local detail="$5"
    local timestamp
    timestamp="$(date '+%F %T')"

    debug "ประมวลผล: $type | $target -> $status (${latency}ms, $detail)"

    # 1. ส่งต่อให้โมดูลแจ้งเตือนและตรวจจับ state change (คนที่ 3)
    if declare -f handle_state_alert >/dev/null; then
        handle_state_alert "$target" "$status" "$DRY_RUN"
    else
        # Mock ไว้ก่อนระหว่างรอเพื่อนคนที่ 3 ส่งโค้ดมาต่อ
        debug "[Hook] รอเชื่อมต่อ handle_state_alert: $target -> $status"
    fi

    # 2. ส่งต่อให้โมดูลบันทึก CSV และประมวลผล Uptime (คนที่ 2)
    if declare -f record_metric >/dev/null; then
        record_metric "$timestamp" "$target" "$type" "$status" "$latency" "$detail" "$DRY_RUN"
    else
        # Mock บันทึกออกหน้าจอชั่วคราวระหว่างรอโมดูล metric
        if (( VERBOSE )); then
            echo "[METRIC RAW] $timestamp,$target,$type,$status,$latency,$detail"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
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

    # โหลดโมดูลย่อย
    if [[ -f "${SCRIPT_DIR}/prober.sh" ]]; then
        # shellcheck source=/dev/null
        source "${SCRIPT_DIR}/prober.sh"
    else
        log ERROR "ไม่พบไฟล์โมดูล ${SCRIPT_DIR}/prober.sh"
        exit 1
    fi

    # โหลดโมดูล metric.sh และ state_alert.sh หากมีไฟล์อยู่แล้ว
    [[ -f "${SCRIPT_DIR}/metric.sh" ]] && source "${SCRIPT_DIR}/metric.sh"
    [[ -f "${SCRIPT_DIR}/state_alert.sh" ]] && source "${SCRIPT_DIR}/state_alert.sh"

    # ตรวจสอบเครื่องมือพื้นฐานที่จำเป็น
    check_deps date awk grep curl nc
    prober_check_deps

    log INFO "SiteWatch เริ่มต้นการตรวจสอบเป้าหมาย..."
    debug "ใช้ไฟล์ config: $CONFIG_FILE"

    # รันการตรวจสอบทั้งหมด
    run_probes

    # ถ้ามีฟังก์ชันสรุป uptime จากโมดูลของเพื่อน ให้เรียกแสดงผล
    if declare -f display_uptime_summary >/dev/null; then
        display_uptime_summary
    fi

    log INFO "การตรวจสอบเสร็จสิ้นสมบูรณ์"
}

main "$@"