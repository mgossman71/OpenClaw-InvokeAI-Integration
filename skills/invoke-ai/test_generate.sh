#!/bin/bash
# Test suite for generate.sh
# Usage: cd /root/.openclaw/workspace/skills/invoke-ai && bash test_generate.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATE_SH="$SCRIPT_DIR/generate.sh"
INVOKEAI_URL="http://10.0.0.144:9090"
TEST_OUTPUT_DIR="/tmp/invokeai_tests_$$"
mkdir -p "$TEST_OUTPUT_DIR"

PASSED=0
FAILED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() {
    printf "${GREEN}✓ PASS${NC}: %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf "${RED}✗ FAIL${NC}: %s\n" "$1"
    FAILED=$((FAILED + 1))
}

# Test 1: Script exists and is executable
echo "=== Test 1: Script exists and is executable ==="
if [ -x "$GENERATE_SH" ]; then
    pass "generate.sh is executable"
else
    fail "generate.sh is not executable"
fi

# Test 2: Missing prompt shows error
echo ""
echo "=== Test 2: Missing prompt shows error ==="
output=$(bash "$GENERATE_SH" 2>&1 || true)
if echo "$output" | grep -q "Error: --prompt is required"; then
    pass "Missing prompt error displayed"
else
    fail "Missing prompt error not displayed"
fi

# Test 3: Server connectivity
echo ""
echo "=== Test 3: Server connectivity ==="
if curl -s "$INVOKEAI_URL/api/v2/models/" >/dev/null 2>&1; then
    pass "InvokeAI server is reachable at $INVOKEAI_URL"
else
    fail "InvokeAI server is NOT reachable at $INVOKEAI_URL"
fi

# Test 4: Model list returns valid JSON
echo ""
echo "=== Test 4: Model list returns valid JSON ==="
models_json=$(curl -s "$INVOKEAI_URL/api/v2/models/?limit=10" 2>/dev/null)
if echo "$models_json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    pass "Model list is valid JSON"
else
    fail "Model list is NOT valid JSON"
fi

# Test 5: At least one FLUX model exists
echo ""
echo "=== Test 5: At least one FLUX model exists ==="
flux_models=$(echo "$models_json" | python3 -c "import json,sys; data=json.load(sys.stdin); models=[m for m in data.get('models',[]) if m.get('base')=='flux']; print(len(models))" 2>/dev/null)
if [ "$flux_models" -gt 0 ] 2>/dev/null; then
    pass "Found $flux_models FLUX model(s)"
else
    fail "No FLUX models found"
fi

# Test 6: Required sub-models exist for FLUX
echo ""
echo "=== Test 6: Required FLUX sub-models exist ==="
t5_count=$(echo "$models_json" | python3 -c "import json,sys; data=json.load(sys.stdin); count=sum(1 for m in data.get('models',[]) if m.get('type')=='t5_encoder'); print(count)" 2>/dev/null)
clip_count=$(echo "$models_json" | python3 -c "import json,sys; data=json.load(sys.stdin); count=sum(1 for m in data.get('models',[]) if m.get('type')=='clip_embed'); print(count)" 2>/dev/null)
vae_count=$(echo "$models_json" | python3 -c "import json,sys; data=json.load(sys.stdin); count=sum(1 for m in data.get('models',[]) if m.get('type')=='vae' and 'flux' in m.get('name','').lower()); print(count)" 2>/dev/null)

if [ "$t5_count" -gt 0 ] 2>/dev/null; then
    pass "Found $t5_count T5 encoder model(s)"
else
    fail "No T5 encoder models found"
fi

if [ "$clip_count" -gt 0 ] 2>/dev/null; then
    pass "Found $clip_count CLIP embed model(s)"
else
    fail "No CLIP embed models found"
fi

if [ "$vae_count" -gt 0 ] 2>/dev/null; then
    pass "Found $vae_count FLUX VAE model(s)"
else
    fail "No FLUX VAE models found"
fi

# Test 7: Generate a small FLUX image (integration test)
echo ""
echo "=== Test 7: Generate a small FLUX image (integration test) ==="
TEST_OUTPUT="$TEST_OUTPUT_DIR/test_flux.png"

# Get first FLUX model key (exclude fill/inpaint models)
flux_model_key=$(echo "$models_json" | python3 -c "import json,sys; data=json.load(sys.stdin); m=next((m for m in data.get('models',[]) if m.get('base')=='flux' and m.get('type')=='main' and 'fill' not in m.get('name','').lower()), None); print(m['key'] if m else '')" 2>/dev/null)

if [ -z "$flux_model_key" ]; then
    fail "No FLUX model key found"
else
    echo "Using FLUX model: $flux_model_key"
    
    # Run generation (small/fast)
    if bash "$GENERATE_SH" \
        --prompt "simple geometric shapes, abstract, minimal colors" \
        --model "$flux_model_key" \
        --steps 4 \
        --guidance 3.5 \
        --width 512 \
        --height 512 \
        --seed 42 \
        --output "$TEST_OUTPUT" 2>&1; then
        
        if [ -f "$TEST_OUTPUT" ]; then
            file_size=$(stat -c%s "$TEST_OUTPUT" 2>/dev/null || stat -f%z "$TEST_OUTPUT" 2>/dev/null)
            if [ "$file_size" -gt 1000 ]; then
                pass "FLUX image generated successfully ($file_size bytes)"
            else
                fail "FLUX image too small ($file_size bytes)"
            fi
        else
            fail "FLUX image file not created"
        fi
    else
        fail "FLUX generation command failed"
    fi
fi

# Test 8: Generate a small SDXL image (integration test)
echo ""
echo "=== Test 8: Generate a small SDXL image (integration test) ==="
TEST_OUTPUT_SDXL="$TEST_OUTPUT_DIR/test_sdxl.png"

# Get first SDXL model key
sdxl_model_key=$(echo "$models_json" | python3 -c "import json,sys; data=json.load(sys.stdin); m=next((m for m in data.get('models',[]) if m.get('base')=='sdxl' and m.get('type')=='main'), None); print(m['key'] if m else '')" 2>/dev/null)

if [ -z "$sdxl_model_key" ]; then
    echo "  ⚠ No SDXL model found, skipping SDXL test"
else
    echo "Using SDXL model: $sdxl_model_key"
    
    if bash "$GENERATE_SH" \
        --prompt "simple geometric shapes, abstract, minimal colors" \
        --model "$sdxl_model_key" \
        --steps 4 \
        --cfg 7.5 \
        --width 512 \
        --height 512 \
        --seed 42 \
        --output "$TEST_OUTPUT_SDXL" 2>&1; then
        
        if [ -f "$TEST_OUTPUT_SDXL" ]; then
            file_size=$(stat -c%s "$TEST_OUTPUT_SDXL" 2>/dev/null || stat -f%z "$TEST_OUTPUT_SDXL" 2>/dev/null)
            if [ "$file_size" -gt 1000 ]; then
                pass "SDXL image generated successfully ($file_size bytes)"
            else
                fail "SDXL image too small ($file_size bytes)"
            fi
        else
            fail "SDXL image file not created"
        fi
    else
        fail "SDXL generation command failed"
    fi
fi

# Test 9: Model info endpoint returns correct base
echo ""
echo "=== Test 9: Model info endpoint returns correct base ==="
if [ -n "$flux_model_key" ]; then
    model_info=$(curl -s "$INVOKEAI_URL/api/v2/models/i/$flux_model_key" 2>/dev/null)
    model_base=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('base',''))" 2>/dev/null)
    if [ "$model_base" = "flux" ]; then
        pass "Model info returns correct base (flux)"
    else
        fail "Model info returns wrong base: $model_base"
    fi
fi

# Test 10: Queue status endpoint works
echo ""
echo "=== Test 10: Queue status endpoint works ==="
queue_status=$(curl -s "$INVOKEAI_URL/api/v1/queue/default/status" 2>/dev/null)
if echo "$queue_status" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    pass "Queue status endpoint returns valid JSON"
else
    fail "Queue status endpoint does NOT return valid JSON"
fi

# Cleanup
rm -rf "$TEST_OUTPUT_DIR"

# Summary
echo ""
echo "========================================"
echo "Test Results: $PASSED passed, $FAILED failed"
echo "========================================"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
