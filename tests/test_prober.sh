#!/usr/bin/env bash
set -euo pipefail

# สีสำหรับแสดงผลการทดสอบ
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ดึงฟังก์ชันจากโมดูล prober.sh เข้ามาทดสอบ
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../bin/prober.sh"

# 1. Mock ฟังก์ชัน log/debug ชั่วคราว (เพราะตอนรันเดี่ยวๆ ไม่มี sitewatch.sh คอยคุม)
log() { echo "[$1] $2"; }
debug() { :; }

# ฟังก์ชันตัวช่วยตรวจเช็คผลการเทส (Assertion Helper)
assert_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected"* ]]; then
        echo -e "[PASS] ${test_name} -> ได้รับ: ${GREEN}${actual}${NC}"
    else
        echo -e "[FAIL] ${test_name} -> คาดหวัง: ${expected} แต่ได้: ${RED}${actual}${NC}"
        return 1
    fi
}

echo "=== เริ่มต้นรัน UNIT TEST: prober.sh ==="

# ----------------------------------------------------
# เทส 1: probe_http
# ----------------------------------------------------
echo -e "\n[1] ทดสอบ HTTP Probe:"

# เทสเว็บปกติ (ต้องได้ UP และ status code 200)
res=$(probe_http "https://www.google.com")
assert_result "Google (เว็บที่เปิดปกติ)" "UP" "$res"

# เทสเว็บจำลอง Error 503 (ต้องได้ DOWN และ status code 503)
res=$(probe_http "https://httpstat.us/503")
assert_result "HTTP 503 Error" "DOWN" "$res"

# ----------------------------------------------------
# เทส 2: probe_dns
# ----------------------------------------------------
echo -e "\n[2] ทดสอบ DNS Resolution Probe:"

# เทสโดเมนที่มีอยู่จริง (ต้อง Resolve ได้ IP)
res=$(probe_dns "google.com")
assert_result "Resolve google.com" "UP" "$res"

# เทสโดเมนมั่วที่ไม่มีอยู่จริง (ต้อง Resolve ไม่ได้)
res=$(probe_dns "domain-test-nonexistent-12345.org")
assert_result "Resolve โดเมนปลอม" "DOWN" "$res"

# ----------------------------------------------------
# เทส 3: probe_port
# ----------------------------------------------------
echo -e "\n[3] ทดสอบ TCP Port Probe:"

# เทสพอร์ตที่เปิดปกติ (DNS 1.1.1.1 พอร์ต 53 หรือ HTTPS google.com พอร์ต 443)
res=$(probe_port "1.1.1.1:53")
assert_result "พอร์ต 53 บน 1.1.1.1 (Cloudflare DNS)" "UP" "$res"

# เทสพอร์ตปิดบน Localhost (พอร์ต 9999 ที่ไม่มีใครรัน)
res=$(probe_port "127.0.0.1:9999")
assert_result "พอร์ตที่ปิดอยู่ (127.0.0.1:9999)" "DOWN" "$res"

echo -e "\n=== ทดสอบเสร็จสิ้น ทุกฟังก์ชันทำงานถูกต้อง ==="