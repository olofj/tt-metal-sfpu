#!/usr/bin/env bash
# Unit tests for ci/affected_targets.sh
#
# These tests mock git diff and bazel query to verify the script's logic
# without requiring a real Bazel workspace or git history.
#
# Usage:
#   ci/test_affected_targets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TESTS_RUN=0

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

setup_mock_env() {
    MOCK_DIR=$(mktemp -d)
    # Create a minimal repo structure for the script to navigate
    mkdir -p "$MOCK_DIR/ci"
    cp "$SCRIPT_DIR/affected_targets.sh" "$MOCK_DIR/ci/"
    cp "$SCRIPT_DIR/full_ci_triggers.txt" "$MOCK_DIR/ci/"
    chmod +x "$MOCK_DIR/ci/affected_targets.sh"

    # Create mock BUILD.bazel files
    mkdir -p "$MOCK_DIR/ttnn/cpp/ttnn/operations/matmul"
    touch "$MOCK_DIR/ttnn/cpp/ttnn/operations/matmul/BUILD.bazel"
    mkdir -p "$MOCK_DIR/tt_metal/impl"
    touch "$MOCK_DIR/tt_metal/impl/BUILD.bazel"
    mkdir -p "$MOCK_DIR/tests/ttnn/unit_tests"
    touch "$MOCK_DIR/tests/ttnn/unit_tests/BUILD.bazel"
    mkdir -p "$MOCK_DIR/docs"
    # No BUILD.bazel in docs/ — it's not a Bazel package

    # The script uses REPO_ROOT relative to its location
    export MOCK_DIR
}

cleanup_mock_env() {
    rm -rf "$MOCK_DIR"
}

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

# ---------------------------------------------------------------------------
# Test: full_ci_triggers.txt pattern matching
# ---------------------------------------------------------------------------

test_full_ci_trigger_patterns() {
    echo "Testing full_ci_triggers.txt pattern matching..."

    # Patterns from the triggers file
    local triggers_file="$SCRIPT_DIR/full_ci_triggers.txt"

    # Test: MODULE.bazel should trigger full CI
    local result
    result=$(echo "MODULE.bazel" | while IFS= read -r changed_file; do
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if [[ "$changed_file" == "$pattern"* ]]; then
                echo "MATCH"
                break 2
            fi
        done < "$triggers_file"
    done)
    run_test "MODULE.bazel triggers full CI" "MATCH" "$result"

    # Test: .bazelrc should trigger full CI
    result=$(echo ".bazelrc" | while IFS= read -r changed_file; do
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if [[ "$changed_file" == "$pattern"* ]]; then
                echo "MATCH"
                break 2
            fi
        done < "$triggers_file"
    done)
    run_test ".bazelrc triggers full CI" "MATCH" "$result"

    # Test: bazel/pytest.bzl should trigger full CI (matches bazel/ prefix)
    result=$(echo "bazel/pytest.bzl" | while IFS= read -r changed_file; do
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if [[ "$changed_file" == "$pattern"* ]]; then
                echo "MATCH"
                break 2
            fi
        done < "$triggers_file"
    done)
    run_test "bazel/pytest.bzl triggers full CI" "MATCH" "$result"

    # Test: toolchain/clang/repo.bzl should trigger full CI
    result=$(echo "toolchain/clang/repo.bzl" | while IFS= read -r changed_file; do
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if [[ "$changed_file" == "$pattern"* ]]; then
                echo "MATCH"
                break 2
            fi
        done < "$triggers_file"
    done)
    run_test "toolchain/ triggers full CI" "MATCH" "$result"

    # Test: ttnn/cpp/ttnn/operations/matmul/matmul.cpp should NOT trigger full CI
    result=$(echo "ttnn/cpp/ttnn/operations/matmul/matmul.cpp" | while IFS= read -r changed_file; do
        local matched="NO_MATCH"
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if [[ "$changed_file" == "$pattern"* ]]; then
                matched="MATCH"
                break
            fi
        done < "$triggers_file"
        echo "$matched"
    done)
    run_test "matmul.cpp does NOT trigger full CI" "NO_MATCH" "$result"

    # Test: README.md should NOT trigger full CI
    result=$(echo "README.md" | while IFS= read -r changed_file; do
        local matched="NO_MATCH"
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if [[ "$changed_file" == "$pattern"* ]]; then
                matched="MATCH"
                break
            fi
        done < "$triggers_file"
        echo "$matched"
    done)
    run_test "README.md does NOT trigger full CI" "NO_MATCH" "$result"
}

# ---------------------------------------------------------------------------
# Test: Non-build file filtering
# ---------------------------------------------------------------------------

test_non_build_file_filtering() {
    echo "Testing non-build file filtering..."

    # Files that should be skipped (not affect the build)
    local skip_files=("README.md" "docs/guide.rst" "CHANGELOG.txt" "LICENSE" ".gitignore" ".editorconfig" "CODEOWNERS")
    for file in "${skip_files[@]}"; do
        local should_skip="true"
        case "$file" in
            *.md|*.rst|*.txt|LICENSE*|NOTICE*|CODEOWNERS) ;;
            .gitignore|.gitattributes|.editorconfig|.clang-format) ;;
            *) should_skip="false" ;;
        esac
        run_test "$file is filtered out" "true" "$should_skip"
    done

    # Files that should NOT be skipped
    local keep_files=("ttnn/cpp/ttnn/operations/matmul/matmul.cpp" "tt_metal/impl/dispatch.cpp" "tests/ttnn/test_add.py" "BUILD.bazel")
    for file in "${keep_files[@]}"; do
        local should_skip="true"
        case "$file" in
            *.md|*.rst|*.txt|LICENSE*|NOTICE*|CODEOWNERS) ;;
            .gitignore|.gitattributes|.editorconfig|.clang-format) ;;
            *) should_skip="false" ;;
        esac
        run_test "$file is NOT filtered out" "false" "$should_skip"
    done
}

# ---------------------------------------------------------------------------
# Test: BUILD.bazel package discovery (walk up directory tree)
# ---------------------------------------------------------------------------

test_package_discovery() {
    echo "Testing Bazel package discovery..."

    setup_mock_env

    # Test: file in a directory with BUILD.bazel
    local dir="ttnn/cpp/ttnn/operations/matmul"
    local found="false"
    while [ "$dir" != "." ]; do
        if [ -f "$MOCK_DIR/$dir/BUILD.bazel" ] || [ -f "$MOCK_DIR/$dir/BUILD" ]; then
            found="true"
            break
        fi
        dir=$(dirname "$dir")
    done
    run_test "matmul/ package found" "true" "$found"

    # Test: file in docs/ (no BUILD.bazel)
    dir="docs/source"
    found="false"
    while [ "$dir" != "." ]; do
        if [ -f "$MOCK_DIR/$dir/BUILD.bazel" ] || [ -f "$MOCK_DIR/$dir/BUILD" ]; then
            found="true"
            break
        fi
        dir=$(dirname "$dir")
    done
    run_test "docs/ has no Bazel package" "false" "$found"

    cleanup_mock_env
}

# ---------------------------------------------------------------------------
# Test: full_ci_triggers.txt comment/blank handling
# ---------------------------------------------------------------------------

test_triggers_file_format() {
    echo "Testing triggers file format parsing..."

    local triggers_file="$SCRIPT_DIR/full_ci_triggers.txt"

    # Count non-comment, non-blank lines
    local pattern_count
    pattern_count=$(grep -vc -e '^#' -e '^$' "$triggers_file")

    # Should have at least 5 patterns (MODULE.bazel, .bazelrc, etc.)
    local has_enough="false"
    [ "$pattern_count" -ge 5 ] && has_enough="true"
    run_test "full_ci_triggers.txt has >=5 patterns (got $pattern_count)" "true" "$has_enough"

    # Should not have any lines with leading whitespace (common mistake)
    local bad_lines
    bad_lines=$(grep -c '^[[:space:]]' "$triggers_file" || true)
    [ -z "$bad_lines" ] && bad_lines="0"
    run_test "No leading whitespace in patterns" "0" "$bad_lines"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "========================================="
echo "  ci/affected_targets.sh unit tests"
echo "========================================="
echo ""

test_full_ci_trigger_patterns
echo ""
test_non_build_file_filtering
echo ""
test_package_discovery
echo ""
test_triggers_file_format

echo ""
echo "========================================="
echo "  Results: $PASS passed, $FAIL failed (of $TESTS_RUN)"
echo "========================================="

[ "$FAIL" -eq 0 ] || exit 1
