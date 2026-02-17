#!/usr/bin/env bash
# Generate negative Bazel target patterns from the TTSim skip list.
#
# Reads tests/pipeline_reorg/ttsim-skip-list.yaml and outputs Bazel
# target patterns for tests that should be excluded when running under
# TTSim for a given architecture.
#
# Usage:
#   ci/ttsim_skip_targets.sh <arch>
#
# Arguments:
#   arch — Architecture section from the skip list (wormhole_b0 or blackhole)
#
# Output:
#   Newline-separated negative Bazel target patterns, e.g.:
#     -//tests/ttnn/unit_tests/operations/eltwise:test_binary_int32
#     -//tests/ttnn/unit_tests/operations/ccl/...
#
# Dependencies:
#   yq (YAML processor) — available in CI images

set -euo pipefail

ARCH="${1:?Usage: $0 <arch>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKIP_LIST="$REPO_ROOT/tests/pipeline_reorg/ttsim-skip-list.yaml"

if [ ! -f "$SKIP_LIST" ]; then
    echo "Skip list not found: $SKIP_LIST" >&2
    exit 1
fi

# Read all entries for the given architecture.
# Each entry is either a directory (ends with /) or a file path (.py).
ENTRIES=$(yq -r ".${ARCH}[]" "$SKIP_LIST" 2>/dev/null) || {
    echo "No entries found for arch '$ARCH' in $SKIP_LIST" >&2
    exit 1
}

while IFS= read -r entry; do
    [ -z "$entry" ] && continue

    if [[ "$entry" == */ ]]; then
        # Directory entry — exclude all targets under that package.
        # Strip trailing slash for Bazel label format.
        pkg="${entry%/}"
        echo "-//${pkg}/..."
    elif [[ "$entry" == *.py ]]; then
        # File entry — map to individual Bazel target.
        # tests/ttnn/.../test_foo.py → //tests/ttnn/...:test_foo
        dir=$(dirname "$entry")
        base=$(basename "$entry" .py)
        echo "-//${dir}:${base}"
    else
        echo "Warning: unrecognized skip list entry: $entry" >&2
    fi
done <<< "$ENTRIES"
