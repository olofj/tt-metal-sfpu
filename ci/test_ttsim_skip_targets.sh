#!/usr/bin/env bash
# Unit tests for ci/ttsim_skip_targets.sh
#
# Verifies that the skip list converter correctly translates
# ttsim-skip-list.yaml entries into negative Bazel target patterns.
#
# Usage:
#   ci/test_ttsim_skip_targets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TESTS_RUN=0

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

run_test() {
    local name="$1"
    local expected="$2"
    local actual="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local name="$1"
    local needle="$2"
    local haystack="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name"
        echo "    expected output to contain: $needle"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local name="$1"
    local needle="$2"
    local haystack="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  FAIL: $name"
        echo "    expected output NOT to contain: $needle"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    fi
}

# ---------------------------------------------------------------------------
# Test: Directory entries produce /... patterns
# ---------------------------------------------------------------------------

test_directory_entries() {
    echo "Testing directory entry conversion..."

    local output
    output=$("$SCRIPT_DIR/ttsim_skip_targets.sh" wormhole_b0)

    # Directory entries should produce -//<path>/... patterns
    assert_contains \
        "CCL directory → //.../ pattern" \
        "-//tests/ttnn/unit_tests/operations/ccl/..." \
        "$output"

    assert_contains \
        "nightly/tg directory → //.../ pattern" \
        "-//tests/nightly/tg/..." \
        "$output"

    assert_contains \
        "nightly/t3000 directory → //.../ pattern" \
        "-//tests/nightly/t3000/..." \
        "$output"
}

# ---------------------------------------------------------------------------
# Test: File entries produce :target patterns
# ---------------------------------------------------------------------------

test_file_entries() {
    echo "Testing file entry conversion..."

    local output
    output=$("$SCRIPT_DIR/ttsim_skip_targets.sh" wormhole_b0)

    # .py file entries should produce -//<dir>:<name_without_py> patterns
    assert_contains \
        "test_multi_device.py → :test_multi_device" \
        "-//tests/ttnn/unit_tests/base_functionality:test_multi_device" \
        "$output"

    assert_contains \
        "test_binary_int32.py → :test_binary_int32" \
        "-//tests/ttnn/unit_tests/operations/eltwise:test_binary_int32" \
        "$output"

    assert_contains \
        "test_topk.py → :test_topk" \
        "-//tests/ttnn/unit_tests/operations/reduce:test_topk" \
        "$output"
}

# ---------------------------------------------------------------------------
# Test: All entries start with - (negative pattern)
# ---------------------------------------------------------------------------

test_all_negative() {
    echo "Testing all entries are negative patterns..."

    local output
    output=$("$SCRIPT_DIR/ttsim_skip_targets.sh" wormhole_b0)

    local non_negative
    non_negative=$(echo "$output" | grep -vc '^-' || true)
    run_test "All wormhole_b0 entries start with -" "0" "$non_negative"

    output=$("$SCRIPT_DIR/ttsim_skip_targets.sh" blackhole)
    non_negative=$(echo "$output" | grep -vc '^-' || true)
    run_test "All blackhole entries start with -" "0" "$non_negative"
}

# ---------------------------------------------------------------------------
# Test: Architecture-specific entries
# ---------------------------------------------------------------------------

test_arch_specific() {
    echo "Testing architecture-specific skip entries..."

    local wh_output bh_output

    wh_output=$("$SCRIPT_DIR/ttsim_skip_targets.sh" wormhole_b0)
    bh_output=$("$SCRIPT_DIR/ttsim_skip_targets.sh" blackhole)

    # Blackhole has extra entries not in wormhole_b0
    assert_contains \
        "Blackhole has BH-specific test_prefetcher_BH" \
        "test_prefetcher_BH" \
        "$bh_output"

    assert_not_contains \
        "Wormhole does NOT have test_prefetcher_BH" \
        "test_prefetcher_BH" \
        "$wh_output"

    # Both architectures share common entries
    assert_contains \
        "Wormhole has test_matmul skip" \
        ":test_matmul" \
        "$wh_output"

    assert_contains \
        "Blackhole has test_matmul skip" \
        ":test_matmul" \
        "$bh_output"
}

# ---------------------------------------------------------------------------
# Test: Output count is reasonable
# ---------------------------------------------------------------------------

test_output_count() {
    echo "Testing output count..."

    local wh_count bh_count

    wh_count=$("$SCRIPT_DIR/ttsim_skip_targets.sh" wormhole_b0 | wc -l)
    bh_count=$("$SCRIPT_DIR/ttsim_skip_targets.sh" blackhole | wc -l)

    # Wormhole should have 80+ skip entries (based on current skip list)
    local wh_enough="false"
    [ "$wh_count" -ge 80 ] && wh_enough="true"
    run_test "Wormhole has >=80 skip entries (got $wh_count)" "true" "$wh_enough"

    # Blackhole should have more entries than wormhole (BH-specific extras)
    local bh_more="false"
    [ "$bh_count" -gt "$wh_count" ] && bh_more="true"
    run_test "Blackhole has more skip entries than Wormhole ($bh_count > $wh_count)" "true" "$bh_more"
}

# ---------------------------------------------------------------------------
# Test: Invalid architecture exits with error
# ---------------------------------------------------------------------------

test_invalid_arch() {
    echo "Testing invalid architecture handling..."

    local exit_code=0
    "$SCRIPT_DIR/ttsim_skip_targets.sh" nonexistent_arch >/dev/null 2>&1 || exit_code=$?

    local failed="false"
    [ "$exit_code" -ne 0 ] && failed="true"
    run_test "Invalid arch exits with non-zero" "true" "$failed"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "========================================="
echo "  ci/ttsim_skip_targets.sh unit tests"
echo "========================================="
echo ""

test_directory_entries
echo ""
test_file_entries
echo ""
test_all_negative
echo ""
test_arch_specific
echo ""
test_output_count
echo ""
test_invalid_arch

echo ""
echo "========================================="
echo "  Results: $PASS passed, $FAIL failed (of $TESTS_RUN)"
echo "========================================="

[ "$FAIL" -eq 0 ] || exit 1
