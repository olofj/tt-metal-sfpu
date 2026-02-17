#!/bin/bash
# Smoke test for Bazel-generated CMake package config files.
#
# Verifies that the generated config files reference all required companion
# files (targets exports, version files) and that the targets export files
# define the expected imported targets.
#
# This runs as a Bazel sh_test with the generated files as data deps.

set -euo pipefail

ERRORS=0

fail() {
    echo "FAIL: $1" >&2
    ERRORS=$((ERRORS + 1))
}

# Resolve runfiles path. Bazel places data deps under the runfiles tree.
# The exact path depends on the workspace name.
find_file() {
    local pattern="$1"
    # Try direct path first, then search runfiles
    if [ -f "$pattern" ]; then
        echo "$pattern"
        return
    fi
    local found
    found=$(find . -path "*/$pattern" -type f 2>/dev/null | head -1)
    if [ -z "$found" ]; then
        fail "Could not find file matching: $pattern"
        return 1
    fi
    echo "$found"
}

# ---------------------------------------------------------------------------
# Test 1: tt-metalium-config.cmake includes Metalium.cmake
# ---------------------------------------------------------------------------
metalium_config=$(find_file "packaging/tt-metalium-config.cmake") || true
if [ -n "$metalium_config" ]; then
    if ! grep -q 'include.*Metalium\.cmake' "$metalium_config"; then
        fail "tt-metalium-config.cmake does not include Metalium.cmake"
    fi
    if ! grep -q 'find_dependency(fmt REQUIRED)' "$metalium_config"; then
        fail "tt-metalium-config.cmake missing find_dependency(fmt)"
    fi
    if ! grep -q 'PACKAGE_INIT' "$metalium_config"; then
        fail "tt-metalium-config.cmake missing PACKAGE_INIT expansion"
    fi
    echo "PASS: tt-metalium-config.cmake structure"
fi

# ---------------------------------------------------------------------------
# Test 2: Metalium.cmake defines expected imported targets
# ---------------------------------------------------------------------------
metalium_targets=$(find_file "packaging/Metalium.cmake") || true
if [ -n "$metalium_targets" ]; then
    for target in "TT::Metalium" "TT::tt_stl" "TT::TracyClient" "TT::reflect" "TT::enchantum" "TT::tt-logger"; do
        if ! grep -q "$target" "$metalium_targets"; then
            fail "Metalium.cmake missing target: $target"
        fi
    done
    # Verify library locations
    if ! grep -q 'libtt_metal\.so' "$metalium_targets"; then
        fail "Metalium.cmake missing libtt_metal.so location"
    fi
    if ! grep -q 'libtt_stl\.so' "$metalium_targets"; then
        fail "Metalium.cmake missing libtt_stl.so location"
    fi
    if ! grep -q 'libTracyClient\.so' "$metalium_targets"; then
        fail "Metalium.cmake missing libTracyClient.so location"
    fi
    # Verify prefix computation (4 levels up from lib/cmake/tt-metalium/)
    if ! grep -q 'get_filename_component.*_IMPORT_PREFIX' "$metalium_targets"; then
        fail "Metalium.cmake missing _IMPORT_PREFIX computation"
    fi
    echo "PASS: Metalium.cmake imported targets"
fi

# ---------------------------------------------------------------------------
# Test 3: tt-metalium-config-version.cmake has version placeholder
# ---------------------------------------------------------------------------
metalium_version=$(find_file "packaging/tt-metalium-config-version.cmake") || true
if [ -n "$metalium_version" ]; then
    if ! grep -q 'PACKAGE_VERSION' "$metalium_version"; then
        fail "tt-metalium-config-version.cmake missing PACKAGE_VERSION"
    fi
    if ! grep -q 'SameMajorVersion\|CVF_VERSION_MAJOR' "$metalium_version"; then
        fail "tt-metalium-config-version.cmake missing SameMajorVersion logic"
    fi
    echo "PASS: tt-metalium-config-version.cmake structure"
fi

# ---------------------------------------------------------------------------
# Test 4: tt-nn-config.cmake includes TT-NN.cmake
# ---------------------------------------------------------------------------
nn_config=$(find_file "packaging/tt-nn-config.cmake") || true
if [ -n "$nn_config" ]; then
    if ! grep -q 'include.*TT-NN\.cmake' "$nn_config"; then
        fail "tt-nn-config.cmake does not include TT-NN.cmake"
    fi
    if ! grep -q 'find_dependency(TT-Metalium REQUIRED)' "$nn_config"; then
        fail "tt-nn-config.cmake missing find_dependency(TT-Metalium)"
    fi
    echo "PASS: tt-nn-config.cmake structure"
fi

# ---------------------------------------------------------------------------
# Test 5: TT-NN.cmake defines expected imported targets
# ---------------------------------------------------------------------------
nn_targets=$(find_file "packaging/TT-NN.cmake") || true
if [ -n "$nn_targets" ]; then
    if ! grep -q 'TTNN::TTNN' "$nn_targets"; then
        fail "TT-NN.cmake missing target: TTNN::TTNN"
    fi
    if ! grep -q '_ttnncpp\.so' "$nn_targets"; then
        fail "TT-NN.cmake missing _ttnncpp.so location"
    fi
    if ! grep -q 'TT::Metalium' "$nn_targets"; then
        fail "TT-NN.cmake missing TT::Metalium dependency"
    fi
    if ! grep -q 'get_filename_component.*_IMPORT_PREFIX' "$nn_targets"; then
        fail "TT-NN.cmake missing _IMPORT_PREFIX computation"
    fi
    echo "PASS: TT-NN.cmake imported targets"
fi

# ---------------------------------------------------------------------------
# Test 6: tt-nn-config-version.cmake has version logic
# ---------------------------------------------------------------------------
nn_version=$(find_file "packaging/tt-nn-config-version.cmake") || true
if [ -n "$nn_version" ]; then
    if ! grep -q 'PACKAGE_VERSION' "$nn_version"; then
        fail "tt-nn-config-version.cmake missing PACKAGE_VERSION"
    fi
    echo "PASS: tt-nn-config-version.cmake structure"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "$ERRORS test(s) failed."
    exit 1
fi

echo ""
echo "All CMake config tests passed."
