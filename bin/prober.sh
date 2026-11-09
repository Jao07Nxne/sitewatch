#!/usr/bin/env bash
# prober.sh - โมดูลตรวจสอบสถานะเครือข่ายสำหรับ SiteWatch
# รองรับการตรวจสอบผ่าน curl, getent/dig และ nc

# ตรวจสอบคำสั่งที่จำเป็นต้องมีในระบบสำหรับโมดูล prober
prober_check_deps() {
    local cmd
    # ตรวจหา curl, nc และ getent หรือ dig
    for cmd in curl nc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log ERROR "ไม่พบคำสั่งจำเป็น: $cmd กรุณาติดตั้งก่อนใช้งาน"
            return 1
        fi
    done

    if ! command -v getent >/dev/null 2>&1 && ! command -v dig >/dev/null 2>&1; then
        log ERROR "ไม่พบคำสั่ง getent หรือ dig ในระบบสำหรับการตรวจสอบ DNS"
        return 1
    fi
    return 0
}

# ตรวจสอบ HTTP/HTTPS URL ด้วย curl
# Output รูปแบบ: <STATUS> <LATENCY_MS> <DETAIL>
probe_http() {
    local url="$1"
    local timeout="${PROBE_TIMEOUT:-5}"
    local response
    local status_code
    local latency_sec
    local latency_ms

    # -s: เงียบ, -o /dev/null: ไม่เอา body
    # -w: ดึง http_code และ time_total ออกมา
    response=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" --connect-timeout "$timeout" "$url" 2>/dev/null || echo "000 0.000")

    status_code=$(awk '{print $1}' <<< "$response")
    latency_sec=$(awk '{print $2}' <<< "$response")

    # แปลง latency เป็น millisecond
    latency_ms=$(awk "BEGIN {printf \"%.2f\", $latency_sec * 1000}")

    # เช็คว่า Status Code อยู่ในกลุ่ม 2xx หรือ 3xx ถือว่า UP
    if [[ "$status_code" =~ ^[23][0-9]{2}$ ]]; then
        echo "UP $latency_ms $status_code"
    else
        echo "DOWN $latency_ms $status_code"
    fi
}

# ตรวจสอบการแปลงชื่อโดเมน (DNS Resolution) ด้วย getent หรือ dig
# Output รูปแบบ: <STATUS> <LATENCY_MS> <DETAIL>
probe_dns() {
    local domain="$1"
    local start_time
    local end_time
    local latency_ms
    local ip_addr=""

    start_time=$(date +%s%N)

    # พยายามใช้ getent hosts ก่อน ถ้าไม่มีให้สลับไปใช้ dig
    if command -v getent >/dev/null 2>&1; then
        ip_addr=$(getent hosts "$domain" | awk '{print $1; exit}')
    elif command -v dig >/dev/null 2>&1; then
        ip_addr=$(dig +short +time="${PROBE_TIMEOUT:-5}" "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    fi

    end_time=$(date +%s%N)
    latency_ms=$(awk "BEGIN {printf \"%.2f\", ($end_time - $start_time) / 1000000}")

    if [[ -n "$ip_addr" ]]; then
        echo "UP $latency_ms $ip_addr"
    else
        echo "DOWN $latency_ms RESOLVE_FAILED"
    fi
}

# ตรวจสอบพอร์ต TCP (host:port) ด้วย nc (netcat)
# Output รูปแบบ: <STATUS> <LATENCY_MS> <DETAIL>
probe_port() {
    local target="$1"
    local timeout="${PROBE_TIMEOUT:-5}"
    local host
    local port
    local start_time
    local end_time
    local latency_ms

    host="${target%%:*}"
    port="${target##*:}"

    start_time=$(date +%s%N)

    # -z: scan เท่านั้น ไม่ส่งข้อมูล, -w: timeout
    if nc -z -w "$timeout" "$host" "$port" >/dev/null 2>&1; then
        end_time=$(date +%s%N)
        latency_ms=$(awk "BEGIN {printf \"%.2f\", ($end_time - $start_time) / 1000000}")
        echo "UP $latency_ms OPEN"
    else
        end_time=$(date +%s%N)
        latency_ms=$(awk "BEGIN {printf \"%.2f\", ($end_time - $start_time) / 1000000}")
        echo "DOWN $latency_ms CLOSED_OR_TIMEOUT"
    fi
}

# ฟังก์ชันหลักในการวนลูปตรวจทุกประเภท targets ที่กำหนดไว้ใน config
# เรียก callback hook ส่งผลลัพธ์ต่อให้ metric และ alert
run_probes() {
    local target
    local res
    local status
    local latency
    local detail

    # 1. วนลูปตรวจ HTTP Targets
    if [[ -n "${HTTP_TARGETS[*]:-}" ]]; then
        for target in "${HTTP_TARGETS[@]}"; do
            debug "กำลังตรวจสอบ HTTP: $target"
            res=$(probe_http "$target")
            read -r status latency detail <<< "$res"
            process_probe_result "$target" "HTTP" "$status" "$latency" "$detail"
        done
    fi

    # 2. วนลูปตรวจ DNS Targets
    if [[ -n "${DNS_TARGETS[*]:-}" ]]; then
        for target in "${DNS_TARGETS[@]}"; do
            debug "กำลังตรวจสอบ DNS: $target"
            res=$(probe_dns "$target")
            read -r status latency detail <<< "$res"
            process_probe_result "$target" "DNS" "$status" "$latency" "$detail"
        done
    fi

    # 3. วนลูปตรวจ Port Targets
    if [[ -n "${PORT_TARGETS[*]:-}" ]]; then
        for target in "${PORT_TARGETS[@]}"; do
            debug "กำลังตรวจสอบ TCP Port: $target"
            res=$(probe_port "$target")
            read -r status latency detail <<< "$res"
            process_probe_result "$target" "PORT" "$status" "$latency" "$detail"
        done
    fi
}