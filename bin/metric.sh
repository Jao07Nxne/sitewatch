#!/usr/bin/env bash
set -euo pipefail

if ! declare -f log >/dev/null 2>&1; then
    log() {
        local level="$1"; shift
        local timestamp
        timestamp="$(date '+%F %T')"
        echo "${timestamp} [${level}] $*" >&2
    }
fi

if ! declare -f debug >/dev/null 2>&1; then
    debug() {
        if [[ "${VERBOSE:-0}" -ne 0 ]]; then
            log DEBUG "$*"
        fi
    }
fi

# ------------------------------------------------------------------------------
# หาตำแหน่งไฟล์ CSV ที่เขียนได้
# ------------------------------------------------------------------------------
get_effective_csv_file() {
    local target_file="${CSV_LOG_FILE:-/var/log/sitewatch/metrics.csv}"
    local target_dir

    target_dir="$(dirname "$target_file")"
    if [[ -d "$target_dir" ]]; then
        if [[ ! -w "$target_dir" ]]; then
            echo "/tmp/sitewatch_metrics.csv"
            return 0
        fi
    else
        local parent_dir
        parent_dir="$(dirname "$target_dir")"
        if [[ ! -w "$parent_dir" ]]; then
            echo "/tmp/sitewatch_metrics.csv"
            return 0
        fi
    fi

    echo "$target_file"
    return 0
}

# ------------------------------------------------------------------------------
# 1. บันทึกผลการตรวจสอบลงไฟล์ CSV 
# Arguments:
#   $1 - timestamp : วันเวลาที่ตรวจ (เช่น 2026-11-11 19:42:00)
#   $2 - target    : ชื่อเป้าหมาย (URL, Domain หรือ Host:Port)
#   $3 - type      : ประเภทการตรวจ (HTTP, DNS, PORT)
#   $4 - status    : ผลการตรวจ (UP หรือ DOWN)
#   $5 - latency   : ความหน่วงมิลลิวินาที (ms)
#   $6 - detail    : ข้อมูลเพิ่มเติม (HTTP Code, Resolved IP, OPEN/CLOSED)
#   $7 - dry_run   : 1 ถ้าเปิดโหมด dry-run, 0 ถ้าปกติ
# ------------------------------------------------------------------------------
record_metric() {
    local timestamp="$1"
    local target="$2"
    local type="$3"
    local status="$4"
    local latency="$5"
    local detail="$6"
    local dry_run="${7:-0}"
    local csv_file
    local csv_dir

    # โหมด Dry-run 
    if [[ "$dry_run" -eq 1 ]]; then
        log INFO "[dry-run] record metric: ${timestamp},${target},${type},${status},${latency},${detail}"
        return 0
    fi

    csv_file=$(get_effective_csv_file)
    csv_dir="$(dirname "$csv_file")"

    if [[ ! -d "$csv_dir" ]]; then
        if ! mkdir -p "$csv_dir" 2>/dev/null; then
            csv_file="/tmp/sitewatch_metrics.csv"
        fi
    fi

    if [[ ! -f "$csv_file" || ! -s "$csv_file" ]]; then
        echo "timestamp,target,type,status,latency_ms,detail" > "$csv_file" 2>/dev/null || {
            csv_file="/tmp/sitewatch_metrics.csv"
            echo "timestamp,target,type,status,latency_ms,detail" > "$csv_file"
        }
    fi

    echo "${timestamp},${target},${type},${status},${latency},${detail}" >> "$csv_file"
    debug "บันทึกข้อมูล Metric สำเร็จ: [${target}] -> ${status} (${latency}ms) -> ${csv_file}"
    return 0
}

# ------------------------------------------------------------------------------
# 2. คำนวณเปอร์เซ็นต์ Uptime ของเป้าหมายจากไฟล์ CSV 
# Arguments:
#   $1 - csv_file : ตำแหน่งไฟล์ CSV
#   $2 - target   : ชื่อเป้าหมายที่ต้องการคำนวณ 
# ------------------------------------------------------------------------------
calculate_uptime() {
    local csv_file="$1"
    local target="${2:-}"

    if [[ ! -f "$csv_file" ]]; then
        echo "0.00"
        return 0
    fi

    awk -F',' -v t="$target" '
    NR > 1 {
        # ถ้าไม่ได้ระบุ target ให้คิดรวมทั้งหมด หรือถ้าระบุให้ตรงกับ target ที่กำหนด
        if (t == "" || t == "ALL" || $2 == t) {
            total++
            if ($4 == "UP") {
                up++
            }
        }
    }
    END {
        if (total > 0) {
            printf "%.2f", (up / total) * 100
        } else {
            print "0.00"
        }
    }' "$csv_file" 2>/dev/null || echo "0.00"
    return 0
}

# ------------------------------------------------------------------------------
# 3. ตารางสรุปสถิติ Uptime และ Latency 
# Arguments:
#   $1 - csv_file (ไม่บังคับ): หากไม่ระบุจะค้นหาตำแหน่งอัตโนมัติ
# ------------------------------------------------------------------------------
display_uptime_summary() {
    local csv_file="${1:-}"

    if [[ -z "$csv_file" ]]; then
        csv_file=$(get_effective_csv_file)
        if [[ ! -f "$csv_file" && -f "/tmp/sitewatch_metrics.csv" ]]; then
            csv_file="/tmp/sitewatch_metrics.csv"
        fi
    fi

    if [[ ! -f "$csv_file" || ! -s "$csv_file" ]]; then
        log INFO "ยังไม่มีประวัติการบันทึกในไฟล์ CSV สำหรับคำนวณ Uptime"
        return 0
    fi

    echo ""
    echo "=========================================================================================="
    echo "                              SiteWatch Uptime Summary                                    "
    echo "=========================================================================================="
    printf "%-35s %-7s %-7s %-5s %-6s %-15s %-9s\n" "Target" "Type" "Total" "UP" "DOWN" "AvgLatency(ms)" "Uptime(%)"
    echo "------------------------------------------------------------------------------------------"

    awk -F',' '
    NR > 1 {
        target = $2
        type = $3
        status = $4
        latency = $5 + 0

        if (!seen[target]++) {
            targets[++target_count] = target
            types[target] = type
        }

        totals[target]++
        if (status == "UP") {
            ups[target]++
            total_latency[target] += latency
            valid_latency_count[target]++
        } else {
            downs[target]++
        }

        all_total++
        if (status == "UP") all_up++
    }
    END {
        for (i = 1; i <= target_count; i++) {
            t = targets[i]
            tot = totals[t]
            u = ups[t] + 0
            d = downs[t] + 0
            
            uptime_pct = (tot > 0) ? (u / tot) * 100 : 0
            avg_lat = (valid_latency_count[t] > 0) ? (total_latency[t] / valid_latency_count[t]) : 0

            disp_target = t
            if (length(disp_target) > 34) {
                disp_target = substr(disp_target, 1, 31) "..."
            }

            printf "%-35s %-7s %-7d %-5d %-6d %-15.2f %6.2f%%\n", disp_target, types[t], tot, u, d, avg_lat, uptime_pct
        }

        print "=========================================================================================="
        if (all_total > 0) {
            all_pct = (all_up / all_total) * 100
            printf "Overall System Uptime: %.2f%% (Total Checks: %d, Passed: %d, Failed: %d)\n", all_pct, all_total, all_up, (all_total - all_up)
        }
    }' "$csv_file"

    echo ""
    return 0
}
