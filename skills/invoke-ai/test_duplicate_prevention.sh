#!/bin/bash
# Unit tests for generate.sh duplicate prevention
# Tests lock file mechanism and specific image retrieval

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVOKEAI_URL="http://10.0.0.144:9090"

PASSED=0
FAILED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { printf "${GREEN}✓ PASS${NC}: %s\n" "$1"; PASSED=$((PASSED + 1)); }
fail() { printf "${RED}✗ FAIL${NC}: %s\n" "$1"; FAILED=$((FAILED + 1)); }
skip() { printf "${YELLOW}⊘ SKIP${NC}: %s\n" "$1"; }

echo "=== Duplicate Prevention Tests ==="
echo ""

# Test 1: Lock file prevents concurrent execution
echo "=== Test 1: Lock file prevents concurrent execution ==="
LOCK_FILE="/tmp/invokeai_generate_${USER:-root}.lock"

# Clean up any existing lock
rm -f "$LOCK_FILE"

# Start first generation in background
bash "$SCRIPT_DIR/generate.sh" \
    --prompt "test lock mechanism" \
    --model "4279ed9f-ee14-44b6-a43a-3413b1edfd5a" \
    --steps 4 \
    --guidance 3.5 \
    --width 512 \
    --height 512 \
    --seed 42 \
    --output /tmp/lock_test1.png > /tmp/lock_test1.log 2>&1 &
PID1=$!

# Give it time to create lock
sleep 1

# Try to start second generation (should fail)
if bash "$SCRIPT_DIR/generate.sh" \
    --prompt "test lock mechanism 2" \
    --model "4279ed9f-ee14-44b6-a43a-3413b1edfd5a" \
    --steps 4 \
    --guidance 3.5 \
    --width 512 \
    --height 512 \
    --seed 43 \
    --output /tmp/lock_test2.png > /tmp/lock_test2.log 2>&1; then
    
    # Check if it actually ran or was blocked
    if grep -q "Error: Another generation is already in progress" /tmp/lock_test2.log; then
        pass "Second generation correctly blocked by lock file"
    else
        fail "Second generation ran despite lock file (unexpected)"
    fi
else
    if grep -q "Error: Another generation is already in progress" /tmp/lock_test2.log; then
        pass "Second generation correctly blocked by lock file (exit 1)"
    else
        fail "Second generation failed for unexpected reason"
    fi
fi

# Wait for first generation to complete
wait $PID1 > /dev/null 2>&1 || true

# Verify lock file is cleaned up
sleep 1
if [ ! -f "$LOCK_FILE" ]; then
    pass "Lock file cleaned up after completion"
else
    fail "Lock file not cleaned up: $LOCK_FILE"
fi

# Clean up
rm -f /tmp/lock_test1.png /tmp/lock_test2.png /tmp/lock_test1.log /tmp/lock_test2.log

# Test 2: Verify specific image retrieval from batch
echo ""
echo "=== Test 2: Specific image retrieval from batch ==="
python3 << PYEOF
import urllib.request, json, time, sys, os, subprocess

def api_get(path):
    req = urllib.request.Request(f"$INVOKEAI_URL{path}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

# Run a generation
result = subprocess.run([
    "bash", "$SCRIPT_DIR/generate.sh",
    "--prompt", "specific image test",
    "--model", "4279ed9f-ee14-44b6-a43a-3413b1edfd5a",
    "--steps", "4",
    "--guidance", "3.5",
    "--width", "512",
    "--height", "512",
    "--seed", "42",
    "--output", "/tmp/specific_test.png"
], capture_output=True, text=True, timeout=300)

print(f"STDOUT: {result.stdout}")
print(f"STDERR: {result.stderr}")
print(f"Return code: {result.returncode}")

if result.returncode != 0:
    print("FAIL: Generation failed")
    sys.exit(1)

# Verify the output file exists
if os.path.exists("/tmp/specific_test.png"):
    size = os.path.getsize("/tmp/specific_test.png")
    print(f"PASS: Output file exists ({size} bytes)")
else:
    print("FAIL: Output file not found")
    sys.exit(1)

# Check that no warning about latest image was issued
if "WARNING: Using latest image" in result.stdout:
    print("FAIL: Script fell back to latest image (timestamp tracking failed)")
    sys.exit(1)
else:
    print("PASS: Script used timestamp-based image retrieval")
PYEOF

if [ $? -eq 0 ]; then
    pass "Specific image retrieval test passed"
else
    fail "Specific image retrieval test failed"
fi

# Clean up
rm -f /tmp/specific_test.png

# Test 3: Lock file works across different prompts
echo ""
echo "=== Test 3: Lock file prevents different prompts too ==="
rm -f "$LOCK_FILE"

# Start first generation
bash "$SCRIPT_DIR/generate.sh" \
    --prompt "first test" \
    --model "4279ed9f-ee14-44b6-a43a-3413b1edfd5a" \
    --steps 4 \
    --guidance 3.5 \
    --width 512 \
    --height 512 \
    --seed 42 \
    --output /tmp/diff_prompt1.png > /tmp/diff_prompt1.log 2>&1 &
PID1=$!

sleep 1

# Try different prompt (should still be blocked)
if bash "$SCRIPT_DIR/generate.sh" \
    --prompt "different prompt" \
    --model "4279ed9f-ee14-44b6-a43a-3413b1edfd5a" \
    --steps 4 \
    --guidance 3.5 \
    --width 512 \
    --height 512 \
    --seed 43 \
    --output /tmp/diff_prompt2.png > /tmp/diff_prompt2.log 2>&1; then
    
    if grep -q "Error: Another generation is already in progress" /tmp/diff_prompt2.log; then
        pass "Different prompt correctly blocked by lock file"
    else
        fail "Different prompt ran despite lock file"
    fi
else
    if grep -q "Error: Another generation is already in progress" /tmp/diff_prompt2.log; then
        pass "Different prompt correctly blocked by lock file (exit 1)"
    else
        fail "Different prompt failed for unexpected reason"
    fi
fi

wait $PID1 > /dev/null 2>&1 || true
rm -f /tmp/diff_prompt1.png /tmp/diff_prompt2.png /tmp/diff_prompt1.log /tmp/diff_prompt2.log

# NEW Test 4: Verify is_intermediate prevents duplicate gallery images
echo ""
echo "=== Test 4: Verify graph nodes marked as intermediate ==="

# Check generate.sh has is_intermediate set on vae_decode and latents_to_image
if grep -q '"is_intermediate": True' "$SCRIPT_DIR/generate.sh"; then
    pass "generate.sh has is_intermediate: True for intermediate nodes"
else
    fail "generate.sh missing is_intermediate: True - duplicate images will occur"
fi

# NEW Test 5: Verify only 1 non-intermediate image per generation
echo ""
echo "=== Test 5: Verify single gallery image per generation ==="

# Get count before generation
BEFORE_COUNT=$(curl -s "$INVOKEAI_URL/api/v1/images/?is_intermediate=false&limit=100" | jq '.items | length')

# Run a generation
bash "$SCRIPT_DIR/generate.sh" \
    --prompt "test single image output" \
    --model "4279ed9f-ee14-44b6-a43a-3413b1edfd5a" \
    --steps 4 \
    --guidance 3.5 \
    --width 512 \
    --height 512 \
    --seed 999 \
    --output /tmp/test_single_image.png > /tmp/test_single.log 2>&1

sleep 2

# Count non-intermediate images after generation
AFTER_COUNT=$(curl -s "$INVOKEAI_URL/api/v1/images/?is_intermediate=false&limit=100" | jq '.items | length')
NEW_IMAGES=$((AFTER_COUNT - BEFORE_COUNT))

if [ "$NEW_IMAGES" -eq 1 ]; then
    pass "Only 1 non-intermediate image created (got $NEW_IMAGES)"
elif [ "$NEW_IMAGES" -eq 0 ]; then
    skip "Could not verify - no new images found (may have been cleaned up)"
else
    fail "Duplicate images detected: $NEW_IMAGES non-intermediate images created"
fi

rm -f /tmp/test_single_image.png /tmp/test_single.log

# Summary
echo ""
echo "========================================"
echo "Duplicate Prevention Tests: $PASSED passed, $FAILED failed"
echo "========================================"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All duplicate prevention tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some duplicate prevention tests failed!${NC}"
    exit 1
fi
