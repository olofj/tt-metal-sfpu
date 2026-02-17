#!/bin/bash
# Verifies that the CI tarball (uncompressed) contains the expected directory
# structure matching the CMake build layout. Checks for presence of shared
# libraries, TTNN extension, programming examples, test binaries, and
# runtime firmware files.
#
# Usage: bazel test //packaging:ci_tarball_test

set -euo pipefail

TARBALL="$1"
ERRORS=0

check_dir() {
    local dir="$1"
    local desc="$2"
    if tar -tf "$TARBALL" | grep -q "^${dir}"; then
        echo "PASS: ${desc} (${dir})"
    else
        echo "FAIL: ${desc} — missing ${dir}"
        ERRORS=$((ERRORS + 1))
    fi
}

check_file() {
    local pattern="$1"
    local desc="$2"
    if tar -tf "$TARBALL" | grep -q "$pattern"; then
        echo "PASS: ${desc}"
    else
        echo "FAIL: ${desc} — no match for ${pattern}"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== CI Tarball Content Verification ==="
echo "Tarball: ${TARBALL}"
echo

# Shared libraries in build/lib/
check_file "build/lib/libtt_metal.so" "libtt_metal.so in build/lib/"
check_file "build/lib/libumd.so" "libumd.so in build/lib/"
check_file "build/lib/libtt_stl.so" "libtt_stl.so in build/lib/"
check_file "build/lib/libTracyClient.so" "libTracyClient.so in build/lib/"
check_file "build/lib/_ttnncpp.so" "_ttnncpp.so in build/lib/"

# Nanobind extension
check_file "ttnn/ttnn/_ttnn.so" "_ttnn.so in ttnn/ttnn/"

# Programming examples
check_dir "build/programming_examples/" "Programming examples directory"
check_file "build/programming_examples/metal_example_" "At least one example binary"

# Runtime firmware
check_dir "runtime/hw/" "Runtime firmware directory"
check_file "runtime/hw/lib/" "Runtime firmware .o files"
check_file "runtime/hw/toolchain/" "Runtime toolchain linker scripts"

# Test binaries
check_dir "build/test/" "Test binaries directory"
check_file "build/test/tt_metal/" "tt_metal test binaries"
check_file "build/test/ttnn/" "TTNN test binaries"
check_file "build/test/tt_fabric/" "tt_fabric test binaries"
check_file "build/test/distributed/" "Distributed test binaries"

echo
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: ${ERRORS} checks failed"
    echo
    echo "Tarball contents:"
    tar -tf "$TARBALL" | head -50
    exit 1
else
    echo "ALL CHECKS PASSED"
fi
