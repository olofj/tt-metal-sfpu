#!/bin/bash
# Tests for bazel/stamp_version.sh
#
# Creates temporary git repositories with known tag configurations and verifies
# that stamp_version.sh produces the correct version strings matching
# setuptools_scm's "guess-next-dev" scheme.
#
# Run: bash bazel/stamp_version_test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP_SCRIPT="$SCRIPT_DIR/stamp_version.sh"

PASS=0
FAIL=0
ERRORS=()

# Create a fresh git repo in a temp directory and cd into it
setup_repo() {
    REPO_DIR=$(mktemp -d)
    cd "$REPO_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "init" > file.txt
    git add file.txt
    git commit -q -m "initial"
}

# Clean up temp directory and return to original dir
cleanup_repo() {
    cd /
    rm -rf "$REPO_DIR"
}

# Extract STABLE_VERSION from stamp output
get_version() {
    "$STAMP_SCRIPT" 2>/dev/null | grep "^STABLE_VERSION " | cut -d" " -f2
}

# Extract STABLE_GIT_TAG from stamp output
get_tag() {
    "$STAMP_SCRIPT" 2>/dev/null | grep "^STABLE_GIT_TAG " | cut -d" " -f2
}

# Assert a value equals expected
assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  PASS: $description"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $description: expected '$expected', got '$actual'")
        echo "  FAIL: $description"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
    fi
}

# Make N empty commits
make_commits() {
    local n=$1
    for i in $(seq 1 "$n"); do
        echo "commit $i" >> file.txt
        git add file.txt
        git commit -q -m "commit $i"
    done
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

echo "=== stamp_version.sh tests ==="
echo

# --- Test 1: Exact release tag ---
echo "Test 1: Exact release tag (v1.2.3)"
setup_repo
git tag v1.2.3
assert_eq "version on exact tag v1.2.3" "1.2.3" "$(get_version)"
assert_eq "tag on exact tag v1.2.3" "v1.2.3" "$(get_tag)"
cleanup_repo
echo

# --- Test 2: Commits after release tag (guess-next-dev) ---
echo "Test 2: 5 commits after v1.2.3"
setup_repo
git tag v1.2.3
make_commits 5
assert_eq "version 5 after v1.2.3" "1.2.4.dev5" "$(get_version)"
cleanup_repo
echo

# --- Test 3: Exact RC tag ---
echo "Test 3: Exact RC tag (v1.2.3-rc1)"
setup_repo
git tag v1.2.3-rc1
assert_eq "version on exact tag v1.2.3-rc1" "1.2.3rc1" "$(get_version)"
cleanup_repo
echo

# --- Test 4: Commits after RC tag (guess-next-dev strips rc, bumps patch) ---
echo "Test 4: 10 commits after v1.2.3-rc1"
setup_repo
git tag v1.2.3-rc1
make_commits 10
assert_eq "version 10 after v1.2.3-rc1" "1.2.4.dev10" "$(get_version)"
cleanup_repo
echo

# --- Test 5: Commits after high RC number ---
echo "Test 5: Commits after v0.65.1-rc16 (matches real repo scenario)"
setup_repo
git tag v0.65.1-rc16
make_commits 5
# 0.65.1-rc16 → strip rc → 0.65.1 → bump patch → 0.65.2 → .dev5
assert_eq "version 5 after v0.65.1-rc16" "0.65.2.dev5" "$(get_version)"
cleanup_repo
echo

# --- Test 6: No tags at all (fallback) ---
echo "Test 6: No tags (fallback)"
setup_repo
assert_eq "version with no tags" "0.0.0.dev0" "$(get_version)"
assert_eq "tag with no tags" "untagged" "$(get_tag)"
cleanup_repo
echo

# --- Test 7: Only dev tags (excluded by --exclude) ---
echo "Test 7: Only dev tags (should fallback)"
setup_repo
git tag v0.0.0-dev20260101
make_commits 3
assert_eq "version with only dev tags" "0.0.0.dev0" "$(get_version)"
cleanup_repo
echo

# --- Test 8: Dev tag + release tag (dev excluded) ---
echo "Test 8: Release tag + dev tag (dev excluded)"
setup_repo
git tag v1.0.0
make_commits 2
git tag v1.0.1-dev20260101
make_commits 3
# Should match v1.0.0, distance 5 (2+3 commits); dev tag excluded
assert_eq "version ignoring dev tags" "1.0.1.dev5" "$(get_version)"
cleanup_repo
echo

# --- Test 9: Multiple release tags (latest wins) ---
echo "Test 9: Multiple release tags"
setup_repo
git tag v1.0.0
make_commits 3
git tag v1.1.0
make_commits 2
assert_eq "version from latest tag v1.1.0" "1.1.1.dev2" "$(get_version)"
cleanup_repo
echo

# --- Test 10: Version with major > 0 ---
echo "Test 10: Major version bump"
setup_repo
git tag v2.0.0
make_commits 1
assert_eq "version 1 after v2.0.0" "2.0.1.dev1" "$(get_version)"
cleanup_repo
echo

# --- Test 11: Exact tag on v0.0.0 ---
echo "Test 11: Exact tag v0.0.0"
setup_repo
git tag v0.0.0
assert_eq "version on exact v0.0.0" "0.0.0" "$(get_version)"
cleanup_repo
echo

# --- Test 12: Output format has all expected keys ---
echo "Test 12: All expected keys present"
setup_repo
git tag v1.0.0
output=$("$STAMP_SCRIPT" 2>/dev/null)
assert_eq "has STABLE_VERSION" "1" "$(echo "$output" | grep -c '^STABLE_VERSION ')"
assert_eq "has STABLE_GIT_COMMIT" "1" "$(echo "$output" | grep -c '^STABLE_GIT_COMMIT ')"
assert_eq "has STABLE_GIT_TAG" "1" "$(echo "$output" | grep -c '^STABLE_GIT_TAG ')"
assert_eq "has BUILD_TIMESTAMP" "1" "$(echo "$output" | grep -c '^BUILD_TIMESTAMP ')"
assert_eq "has BUILD_HOST" "1" "$(echo "$output" | grep -c '^BUILD_HOST ')"
cleanup_repo
echo

# --- Test 13: STABLE_GIT_COMMIT is a full SHA ---
echo "Test 13: STABLE_GIT_COMMIT is full SHA"
setup_repo
git tag v1.0.0
commit=$("$STAMP_SCRIPT" 2>/dev/null | grep "^STABLE_GIT_COMMIT " | cut -d" " -f2)
assert_eq "commit is 40 hex chars" "40" "${#commit}"
cleanup_repo
echo

# --- Test 14: RC tag with higher RC number ---
echo "Test 14: Exact RC tag (v2.5.0-rc99)"
setup_repo
git tag v2.5.0-rc99
assert_eq "version on exact tag v2.5.0-rc99" "2.5.0rc99" "$(get_version)"
cleanup_repo
echo

# --- Test 15: Single commit after exact release tag ---
echo "Test 15: 1 commit after v3.0.0"
setup_repo
git tag v3.0.0
make_commits 1
assert_eq "version 1 after v3.0.0" "3.0.1.dev1" "$(get_version)"
cleanup_repo
echo

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then
    echo
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi

echo
echo "All tests passed."
