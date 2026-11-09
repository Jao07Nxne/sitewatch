#!/usr/bin/env bash
# ==============================================================================
# Unit Test สำหรับโมดูล state_alert.sh (คนที่ 3)
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../bin/state_alert.sh"

TEST_STATE_FILE="/tmp/sitewatch_test_state_$$.env"
LOG_CAPTURE=""

# Mock logging functions
log() {
    local level="$1"; shift
    LOG_CAPTURE="${level}: $*"
    echo "  [LOG] ${LOG_CAPTURE}"
}

debug() {
    LOG_CAPTURE="DEBUG: $*"
    # echo "  [DEBUG] ${LOG_CAPTURE}"
}

assert_equals() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo -e "[PASS] ${test_name} -> ${GREEN}${actual}${NC}"
    else
        echo -e "[FAIL] ${test_name} -> คาดหวัง: '${expected}' แต่ได้: '${RED}${actual}${NC}'"
        return 1
    fi
}

cleanup() {
    rm -f "$TEST_STATE_FILE" "${TEST_STATE_FILE}.tmp"* 2>/dev/null || true
}
trap cleanup EXIT

echo "=== เริ่มต้นรัน UNIT TEST: state_alert.sh ==="

# ------------------------------------------------------------------------------
# 1. ทดสอบ get_previous_state เมื่อไฟล์ยังไม่มี
# ------------------------------------------------------------------------------
echo -e "\n[1] ทดสอบ get_previous_state (ไฟล์ยังไม่มี):"
state=$(get_previous_state "$TEST_STATE_FILE" "https://example.com")
assert_equals "เป้าหมายใหม่เมื่อไม่มีไฟล์ state ต้องได้ UNKNOWN" "UNKNOWN" "$state"

# ------------------------------------------------------------------------------
# 2. ทดสอบ save_state และ get_previous_state
# ------------------------------------------------------------------------------
echo -e "\n[2] ทดสอบ save_state และอ่านค่ากลับ:"
save_state "$TEST_STATE_FILE" "https://example.com" "UP" 0
state=$(get_previous_state "$TEST_STATE_FILE" "https://example.com")
assert_equals "อ่านค่าที่เพิ่งบันทึก (UP)" "UP" "$state"

# ทดสอบเพิ่มอีก 1 target
save_state "$TEST_STATE_FILE" "1.1.1.1:53" "DOWN" 0
state1=$(get_previous_state "$TEST_STATE_FILE" "https://example.com")
state2=$(get_previous_state "$TEST_STATE_FILE" "1.1.1.1:53")
assert_equals "อ่าน target แรกยังต้องเป็น UP" "UP" "$state1"
assert_equals "อ่าน target ที่สองต้องได้ DOWN" "DOWN" "$state2"

# ------------------------------------------------------------------------------
# 3. ทดสอบ check_and_notify แต่ละกรณี
# ------------------------------------------------------------------------------
echo -e "\n[3] ทดสอบ check_and_notify การแจ้งเตือนสถานะต่างๆ:"

# Case 3.1: สถานะคงที่ (UP -> UP) ไม่มีการแจ้งเตือน
LOG_CAPTURE=""
check_and_notify "https://example.com" "UP" "UP"
assert_equals "สถานะ UP คงที่ (ไม่มี log เตือน)" "DEBUG: สถานะของ [https://example.com] คงที่: UP (ไม่มีการแจ้งเตือน)" "$LOG_CAPTURE"

# Case 3.2: สถานะเปลี่ยนจาก UP -> DOWN (เว็บล่ม!)
LOG_CAPTURE=""
check_and_notify "https://example.com" "UP" "DOWN"
if [[ "$LOG_CAPTURE" == ERROR:* ]]; then
    echo -e "[PASS] สถานะ UP -> DOWN ต้องส่งแจ้งเตือนระดับ ${GREEN}ERROR${NC}"
else
    echo -e "[FAIL] สถานะ UP -> DOWN คาดหวัง ERROR แต่ได้: ${RED}${LOG_CAPTURE}${NC}"
    exit 1
fi

# Case 3.3: สถานะเปลี่ยนจาก DOWN -> UP (กู้คืนสำเร็จ)
LOG_CAPTURE=""
check_and_notify "https://example.com" "DOWN" "UP"
if [[ "$LOG_CAPTURE" == INFO:* ]]; then
    echo -e "[PASS] สถานะ DOWN -> UP ต้องส่งแจ้งเตือนระดับ ${GREEN}INFO${NC}"
else
    echo -e "[FAIL] สถานะ DOWN -> UP คาดหวัง INFO แต่ได้: ${RED}${LOG_CAPTURE}${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 4. ทดสอบ Dry-run Mode (-n)
# ------------------------------------------------------------------------------
echo -e "\n[4] ทดสอบโหมด Dry-run (ต้องไม่แตะต้องไฟล์จริง):"
save_state "$TEST_STATE_FILE" "https://dryrun-test.com" "UP" 1
state=$(get_previous_state "$TEST_STATE_FILE" "https://dryrun-test.com")
assert_equals "ในโหมด dry-run ต้องไม่ถูกเขียนลงไฟล์จริง" "UNKNOWN" "$state"

# ------------------------------------------------------------------------------
# 5. ทดสอบฟังก์ชันภาพรวม handle_state_alert
# ------------------------------------------------------------------------------
echo -e "\n[5] ทดสอบ handle_state_alert (Hook รวม):"
export STATE_FILE="$TEST_STATE_FILE"
handle_state_alert "https://hook-test.com" "UP" 0
state=$(get_previous_state "$TEST_STATE_FILE" "https://hook-test.com")
assert_equals "handle_state_alert บันทึกสำเร็จ" "UP" "$state"

# สั่งเปลี่ยนสถานะเป็น DOWN ผ่าน handle_state_alert
LOG_CAPTURE=""
handle_state_alert "https://hook-test.com" "DOWN" 0
state=$(get_previous_state "$TEST_STATE_FILE" "https://hook-test.com")
assert_equals "handle_state_alert อัปเดตสถานะเป็น DOWN" "DOWN" "$state"

echo -e "\n=== ทดสอบเสร็จสิ้น โมดูล state_alert.sh ทำงานถูกต้องสมบูรณ์ ==="
