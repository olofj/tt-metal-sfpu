#!/usr/bin/env bash
# Determine which Bazel test targets are affected by the changes in a PR.
#
# Usage:
#   ci/affected_targets.sh [BASE_REF] [HEAD_REF]
#
# Outputs one of:
#   FULL_CI   — foundational paths changed, run everything
#   SKIP      — only non-build files changed (docs, markdown, etc.)
#   <targets> — newline-separated list of affected test targets
#
# Exit codes:
#   0 — success (check stdout for the result)
#   1 — error (e.g., bazel query failure)

set -euo pipefail

BASE_REF="${1:-origin/main}"
HEAD_REF="${2:-HEAD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Step 1: Get list of changed files
# ---------------------------------------------------------------------------
CHANGED_FILES=$(git diff --name-only "${BASE_REF}...${HEAD_REF}" 2>/dev/null \
    || git diff --name-only "${BASE_REF}" "${HEAD_REF}")

if [ -z "$CHANGED_FILES" ]; then
    echo "SKIP"
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 2: Check if any changed file triggers full CI
# ---------------------------------------------------------------------------
TRIGGERS_FILE="$SCRIPT_DIR/full_ci_triggers.txt"

if [ -f "$TRIGGERS_FILE" ]; then
    while IFS= read -r pattern; do
        # Skip comments and blank lines
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue

        while IFS= read -r changed_file; do
            if [[ "$changed_file" == "$pattern"* ]]; then
                echo "FULL_CI" >&2
                echo "  trigger: $changed_file matches pattern '$pattern'" >&2
                echo "FULL_CI"
                exit 0
            fi
        done <<< "$CHANGED_FILES"
    done < "$TRIGGERS_FILE"
fi

# ---------------------------------------------------------------------------
# Step 3: Filter out non-build files (docs, markdown, YAML configs, etc.)
# ---------------------------------------------------------------------------
BUILD_FILES=""
while IFS= read -r file; do
    case "$file" in
        # Skip documentation and metadata files
        *.md|*.rst|*.txt|LICENSE*|NOTICE*|CODEOWNERS) continue ;;
        # Skip pure config files that don't affect the build graph
        .gitignore|.gitattributes|.editorconfig|.clang-format) continue ;;
        # Skip GitHub-specific files (workflows are caught by full_ci_triggers)
        .github/*.yml|.github/*.yaml) continue ;;
        # Everything else is a potential build-affecting file
        *) BUILD_FILES="${BUILD_FILES}${file}"$'\n' ;;
    esac
done <<< "$CHANGED_FILES"

# Remove trailing newline
BUILD_FILES="${BUILD_FILES%$'\n'}"

if [ -z "$BUILD_FILES" ]; then
    echo "SKIP"
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 4: Convert file paths to Bazel package labels
# ---------------------------------------------------------------------------
# For each changed file, find the nearest BUILD.bazel or BUILD file and
# add that package to our set of affected packages.
declare -A PACKAGES=()

while IFS= read -r file; do
    [ -z "$file" ] && continue

    dir=$(dirname "$file")

    # Walk up the directory tree to find the owning Bazel package.
    while [ "$dir" != "." ]; do
        if [ -f "$REPO_ROOT/$dir/BUILD.bazel" ] || [ -f "$REPO_ROOT/$dir/BUILD" ]; then
            PACKAGES["//$dir:all"]=1
            break
        fi
        dir=$(dirname "$dir")
    done

    # If we reached the root and there's a BUILD file there, include //:all
    if [ "$dir" = "." ]; then
        if [ -f "$REPO_ROOT/BUILD.bazel" ] || [ -f "$REPO_ROOT/BUILD" ]; then
            PACKAGES["//:all"]=1
        fi
    fi
done <<< "$BUILD_FILES"

if [ ${#PACKAGES[@]} -eq 0 ]; then
    echo "SKIP"
    exit 0
fi

# Deduplicate and sort
PACKAGE_LIST=$(printf '%s\n' "${!PACKAGES[@]}" | sort -u)

echo "Affected packages:" >&2
while IFS= read -r pkg; do
    echo "  $pkg" >&2
done <<< "$PACKAGE_LIST"

# ---------------------------------------------------------------------------
# Step 5: Query Bazel for affected test targets
# ---------------------------------------------------------------------------
# Use rdeps() to find all test targets that transitively depend on the
# changed packages. This is the core of affected-target analysis.
PACKAGE_SET=$(echo "$PACKAGE_LIST" | tr '\n' ' ')

AFFECTED_TESTS=$(bazel query \
    "kind('(cc_test|py_test)', rdeps(//..., set($PACKAGE_SET)))" \
    --keep_going \
    --output=label \
    2>/dev/null) || {
    # If bazel query fails (e.g., parse errors), fall back to full CI.
    echo "bazel query failed, falling back to FULL_CI" >&2
    echo "FULL_CI"
    exit 0
}

if [ -z "$AFFECTED_TESTS" ]; then
    echo "No test targets affected" >&2
    echo "SKIP"
    exit 0
fi

TEST_COUNT=$(echo "$AFFECTED_TESTS" | wc -l)
echo "Found $TEST_COUNT affected test targets" >&2

echo "$AFFECTED_TESTS"
