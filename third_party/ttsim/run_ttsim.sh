#!/usr/bin/env bash
# Wrapper script for running Bazel tests under the TTSim simulator.
#
# Used by the ttsim_test() macro in //bazel:ttsim.bzl. Sets up the simulator
# home directory, assembles the JIT runtime tree from Bazel-built artifacts,
# and runs the test binary.
#
# Arguments (set by the macro via sh_test args):
#   $1          — rlocationpath to the TTSim shared library
#   $2          — rlocationpath to the SoC descriptor YAML
#   $3          — rlocationpath to the test binary
#   $4          — rlocationpath to the @sfpi g++ binary
#   $5          — rlocationpath to the runtime hw tree (firmware .o + .ld)
#   $6..        — forwarded to the test binary
#
# Environment (set by the macro via sh_test env):
#   TTSIM_ARCH  — "wormhole_b0" or "blackhole"

set -euo pipefail

ARCH="${TTSIM_ARCH:?TTSIM_ARCH not set}"

# Resolve runfiles directory.
if [[ -n "${RUNFILES_DIR:-}" ]]; then
    RF="$RUNFILES_DIR"
elif [[ -n "${TEST_SRCDIR:-}" ]]; then
    RF="$TEST_SRCDIR"
elif [[ -d "${BASH_SOURCE[0]}.runfiles" ]]; then
    RF="${BASH_SOURCE[0]}.runfiles"
else
    echo "ERROR: Cannot locate runfiles directory" >&2
    exit 1
fi

# Parse arguments — paths are rlocationpaths resolved by Bazel.
TTSIM_LIB_PATH="$1"
SOC_DESC_PATH="$2"
TEST_BIN="$3"
SFPI_GXX_RLOC="$4"
RUNTIME_HW_RLOC="$5"
shift 5

# Resolve relative paths against runfiles.
[[ "$TTSIM_LIB_PATH" != /* ]] && TTSIM_LIB_PATH="$RF/$TTSIM_LIB_PATH"
[[ "$SOC_DESC_PATH" != /* ]] && SOC_DESC_PATH="$RF/$SOC_DESC_PATH"
[[ "$TEST_BIN" != /* ]] && TEST_BIN="$RF/$TEST_BIN"

SFPI_GXX_PATH="$RF/$SFPI_GXX_RLOC"
RUNTIME_HW_PATH="$RF/$RUNTIME_HW_RLOC"

if [[ ! -f "$TTSIM_LIB_PATH" ]]; then
    echo "ERROR: TTSim library not found at: $TTSIM_LIB_PATH" >&2
    exit 1
fi

if [[ ! -f "$SOC_DESC_PATH" ]]; then
    echo "ERROR: SoC descriptor not found at: $SOC_DESC_PATH" >&2
    exit 1
fi

if [[ ! -f "$SFPI_GXX_PATH" ]]; then
    echo "ERROR: SFPI compiler not found at: $SFPI_GXX_PATH" >&2
    exit 1
fi

if [[ ! -d "$RUNTIME_HW_PATH" ]]; then
    echo "ERROR: Runtime hw tree not found at: $RUNTIME_HW_PATH" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Determine workspace root — needed for source headers that the JIT build
# reads at test runtime (tt_metal/hw/inc, tt_metal/kernels, etc.).
#
# The SoC descriptor is a source file in the workspace, so resolving its
# symlink in runfiles gives us the real workspace path.
# ---------------------------------------------------------------------------
SOC_REAL=$(readlink -f "$SOC_DESC_PATH")
# SOC_REAL is e.g. /path/to/tt-metal/tt_metal/soc_descriptors/wormhole_b0_80_arch.yaml
WORKSPACE_ROOT="${SOC_REAL%/tt_metal/soc_descriptors/*}"

if [[ -z "$WORKSPACE_ROOT" || ! -d "$WORKSPACE_ROOT/tt_metal" ]]; then
    echo "ERROR: Cannot determine workspace root from SoC descriptor: $SOC_REAL" >&2
    echo "       Expected tt_metal/ subdirectory at the workspace root." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve SFPI root from the g++ binary path.
# The g++ binary is at <sfpi_root>/compiler/bin/riscv-tt-elf-g++
# ---------------------------------------------------------------------------
SFPI_GXX_REAL=$(readlink -f "$SFPI_GXX_PATH")
SFPI_ROOT=$(dirname "$(dirname "$(dirname "$SFPI_GXX_REAL")")")

if [[ ! -d "$SFPI_ROOT/compiler" ]]; then
    echo "ERROR: SFPI root not found at: $SFPI_ROOT" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Create a temporary root directory that the JIT build system can navigate.
# This assembles Bazel-built artifacts with workspace source paths into
# the layout expected by TT_METAL_RUNTIME_ROOT:
#
#   <tmp>/runtime/sfpi/         → @sfpi compiler tree
#   <tmp>/runtime/hw/           → Bazel-built firmware objects + linker scripts
#   <tmp>/tt_metal/             → workspace source headers and kernels
#   <tmp>/tt_metal/third_party/ → workspace third-party sources
# ---------------------------------------------------------------------------
TMP_ROOT=$(mktemp -d -t ttsim-root.XXXXXX)
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

mkdir -p "$TMP_ROOT/runtime"

# SFPI compiler (from @sfpi external repo)
ln -sf "$SFPI_ROOT" "$TMP_ROOT/runtime/sfpi"

# Firmware objects + linker scripts (from Bazel ttsim_runtime rule)
RUNTIME_HW_REAL=$(readlink -f "$RUNTIME_HW_PATH")
ln -sf "$RUNTIME_HW_REAL" "$TMP_ROOT/runtime/hw"

# Source headers and kernels (from workspace — requires no-sandbox)
ln -sf "$WORKSPACE_ROOT/tt_metal" "$TMP_ROOT/tt_metal"
if [[ -d "$WORKSPACE_ROOT/tt_metal/third_party" ]]; then
    # Already covered by the tt_metal symlink
    :
fi

# ---------------------------------------------------------------------------
# Create simulator home directory with the required layout:
#   libttsim.so         — the simulator shared library
#   soc_descriptor.yaml — the chip architecture descriptor
# ---------------------------------------------------------------------------
SIM_HOME=$(mktemp -d -t ttsim.XXXXXX)
cleanup_all() { rm -rf "$TMP_ROOT" "$SIM_HOME"; }
trap cleanup_all EXIT

ln -s "$(readlink -f "$TTSIM_LIB_PATH")" "$SIM_HOME/libttsim.so"
ln -s "$(readlink -f "$SOC_DESC_PATH")" "$SIM_HOME/soc_descriptor.yaml"

export TT_METAL_SIMULATOR_HOME="$SIM_HOME"
export TT_METAL_SIMULATOR="$SIM_HOME/libttsim.so"
export TT_METAL_SLOW_DISPATCH_MODE=1
export ARCH_NAME="$ARCH"
export TT_METAL_RUNTIME_ROOT="$TMP_ROOT"

exec "$TEST_BIN" "$@"
