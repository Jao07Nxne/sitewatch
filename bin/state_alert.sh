#!/usr/bin/env bash
# ==============================================================================
# Project: SiteWatch - โมดูล State Machine & แจ้งเตือน (คนที่ 3)
# File: state_alert.sh
# ==============================================================================

# อ่านสถานะรอบก่อนหน้าจาก State File
# Arguments:
#   $1 - state_file: ตำแหน่งไฟล์ state
#   $2 - target: ชื่อเป้าหมายที่ต้องการค้นหา
# Output:
#   คืนค่าสถานะเดิม เช่น "UP", "DOWN" หรือ "UNKNOWN" (ถ้ายังไม่เคยบันทึกมาก่อน)
get_previous_state() {
    local state_file="$1"
    local target="$2"
    local match=""

    if [[ ! -f "$state_file" ]]; then
        echo "UNKNOWN"
        return 0
    fi

    # ค้นหาบรรทัดที่ขึ้นต้นด้วย target= ในไฟล์ state
    # ใช้ grep -F เพื่อไม่ให้เครื่องหมายพิเศษใน URL / IP ตีความเป็น regex
    # ใส่ || true เพื่อป้องกัน set -euo pipefail ล้มเหลวเมื่อ grep ไม่พบบรรทัด
    match=$(grep -F "${target}=" "$state_file" 2>/dev/null | tail -n 1 || true)

    if [[ -n "$match" ]]; then
        echo "${match#*=}"
    else
        echo "UNKNOWN"
    fi
}

# ตรวจสอบการเปลี่ยนสถานะและส่งสัญญาณแจ้งเตือน
# Arguments:
#   $1 - target: ชื่อเป้าหมาย
#   $2 - old_state: สถานะเดิม
#   $3 - new_state: สถานะล่าสุด
check_and_notify() {
    local target="$1"
    local old_state="$2"
    local new_state="$3"

    # กรณีที่ 1: สถานะเหมือนเดิม (UP->UP หรือ DOWN->DOWN)
    if [[ "$old_state" == "$new_state" ]]; then
        debug "สถานะของ [${target}] คงที่: ${new_state} (ไม่มีการแจ้งเตือน)"
        return 0
    fi

    # กรณีที่ 2: เริ่มติดตามครั้งแรก (UNKNOWN -> UP / DOWN)
    if [[ "$old_state" == "UNKNOWN" ]]; then
        if [[ "$new_state" == "DOWN" ]]; then
            log WARN "[ALERT] เป้าหมายใหม่ตรวจพบปัญหาทันที: [${target}] สถานะเริ่มต้นเป็น DOWN"
        else
            log INFO "[STATE] เริ่มติดตามเป้าหมายใหม่: [${target}] สถานะเริ่มต้นเป็น UP"
        fi
        return 0
    fi

    # กรณีที่ 3: สถานะเปลี่ยนจาก UP -> DOWN (Service ล่ม!)
    if [[ "$old_state" == "UP" && "$new_state" == "DOWN" ]]; then
        log ERROR "[ALERT] ตรวจพบเหตุขัดข้อง! [${target}] สถานะเปลี่ยนจาก UP -> DOWN"
        return 0
    fi

    # กรณีที่ 4: สถานะเปลี่ยนจาก DOWN -> UP (Service ฟื้นคืนชีพ)
    if [[ "$old_state" == "DOWN" && "$new_state" == "UP" ]]; then
        log INFO "[RECOVERY] บริการกลับมาออนไลน์แล้ว! [${target}] สถานะเปลี่ยนจาก DOWN -> UP"
        return 0
    fi

    # กรณีสถานะอื่นๆ ที่อาจเกิดขึ้น
    log WARN "[STATE] สถานะของ [${target}] เปลี่ยนแปลง: ${old_state} -> ${new_state}"
}

# บันทึกสถานะล่าสุดลงไฟล์ State (รองรับ Dry-run)
# Arguments:
#   $1 - state_file: ตำแหน่งไฟล์ state
#   $2 - target: ชื่อเป้าหมาย
#   $3 - new_state: สถานะใหม่
#   $4 - dry_run: 1 ถ้าเปิดโหมด dry-run, 0 ถ้าปกติ
save_state() {
    local state_file="$1"
    local target="$2"
    local new_state="$3"
    local dry_run="${4:-0}"
    local state_dir
    local temp_file

    if (( dry_run )); then
        log INFO "[dry-run] update state: ${target}=${new_state} -> ${state_file}"
        return 0
    fi

    state_dir="$(dirname "$state_file")"
    if [[ ! -d "$state_dir" ]]; then
        mkdir -p "$state_dir" 2>/dev/null || {
            log WARN "ไม่สามารถสร้างโฟลเดอร์เก็บ state: ${state_dir} (สิทธิ์ไม่เพียงพอ)"
            return 1
        }
    fi

    # บันทึกแบบ Atomic โดยลบบรรทัดเก่าออกแล้วต่อท้ายด้วยค่าใหม่
    temp_file="${state_file}.tmp.$$"
    if [[ -f "$state_file" ]]; then
        grep -v -F "${target}=" "$state_file" > "$temp_file" 2>/dev/null || true
    else
        : > "$temp_file"
    fi

    echo "${target}=${new_state}" >> "$temp_file"
    mv "$temp_file" "$state_file" 2>/dev/null || {
        log WARN "ไม่สามารถเขียนไฟล์ state: ${state_file}"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    }

    debug "อัปเดตไฟล์ State สำเร็จ: ${target}=${new_state}"
}

# ฟังก์ชันหลักที่เป็นจุดเชื่อมโยง (Hook) ให้ sitewatch.sh เรียกใช้งาน
# Arguments:
#   $1 - target: ชื่อเป้าหมาย
#   $2 - new_state: สถานะล่าสุดจากการ probe
#   $3 - dry_run: 1 เมื่อรันโหมด dry-run (-n)
handle_state_alert() {
    local target="$1"
    local new_state="$2"
    local dry_run="${3:-0}"
    local state_file="${STATE_FILE:-/tmp/sitewatch.state}"
    local old_state

    old_state=$(get_previous_state "$state_file" "$target")
    check_and_notify "$target" "$old_state" "$new_state"
    save_state "$state_file" "$target" "$new_state" "$dry_run"
}
