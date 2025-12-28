#!/bin/bash
# Zero - Development Test Suite
# Run tests locally without needing Pi hardware

# Don't use set -e - we want to continue even after failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

test_pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
test_fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }

echo "========================================"
echo "Zero Test Suite"
echo "========================================"
echo ""

# Test 1: Check repo structure
echo "Testing repo structure..."
[ -d "$REPO_DIR/apps/wifi-portal" ] && test_pass "wifi-portal exists" || test_fail "wifi-portal missing"
[ -d "$REPO_DIR/apps/web" ] && test_pass "web app exists" || test_fail "web app missing"
[ -d "$REPO_DIR/apps/display" ] && test_pass "display app exists" || test_fail "display app missing"
[ -d "$REPO_DIR/scripts" ] && test_pass "scripts dir exists" || test_fail "scripts dir missing"
[ -f "$REPO_DIR/scripts/flash.sh" ] && test_pass "flash.sh exists" || test_fail "flash.sh missing"

# Test 2: Check Python syntax
echo ""
echo "Testing Python syntax..."
for py in "$REPO_DIR"/apps/*/app.py; do
    if python3 -m py_compile "$py" 2>/dev/null; then
        test_pass "$(basename $(dirname $py))/app.py syntax OK"
    else
        test_fail "$(basename $(dirname $py))/app.py syntax error"
    fi
done

# Test 3: Check Flask imports
echo ""
echo "Testing Flask imports..."
if python3 -c "from flask import Flask" 2>/dev/null; then
    test_pass "Flask installed"
else
    test_fail "Flask not installed (pip install flask)"
fi

# Test 4: Check bash script syntax
echo ""
echo "Testing bash script syntax..."
for sh in "$REPO_DIR"/scripts/*.sh; do
    if bash -n "$sh" 2>/dev/null; then
        test_pass "$(basename $sh) syntax OK"
    else
        test_fail "$(basename $sh) syntax error"
    fi
done

# Test 5: Check templates exist
echo ""
echo "Testing templates..."
[ -f "$REPO_DIR/apps/wifi-portal/templates/index.html" ] && test_pass "wifi-portal templates" || test_fail "wifi-portal templates missing"
[ -f "$REPO_DIR/apps/web/templates/index.html" ] && test_pass "web templates" || test_fail "web templates missing"

# Test 6: Check systemd services
echo ""
echo "Testing systemd service files..."
for svc in "$REPO_DIR"/rootfs/etc/systemd/system/*.service; do
    if [ -f "$svc" ]; then
        test_pass "$(basename $svc) exists"
    fi
done

# Test 7: Test wifi-portal app can start (briefly)
echo ""
echo "Testing wifi-portal app startup..."
cd "$REPO_DIR/apps/wifi-portal"
timeout 2 python3 -c "
from app import app
print('App created successfully')
" 2>/dev/null && test_pass "wifi-portal app initializes" || test_fail "wifi-portal app fails to initialize"

# Summary
echo ""
echo "========================================"
echo "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "========================================"

exit $FAIL
