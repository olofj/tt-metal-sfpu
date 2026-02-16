"""Validate that the ttnn wheel contains all required components.

Inspects the wheel zip to verify:
  1. Python packages: ttnn, tt_lib, tracy, triage
  2. Native extension: ttnn/_ttnn.so
  3. Runtime firmware: ttnn/runtime/hw/ for all architectures
  4. tt_metal data: SOC descriptors, core descriptors, dispatch kernels
  5. JIT headers: kernel sources under ttnn/ttnn/cpp/
  6. No test files leaked into the wheel
"""

import fnmatch
import os
import sys
import zipfile

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def find_wheel(runfiles_dir):
    """Locate the .whl file in Bazel runfiles."""
    for root, _, files in os.walk(runfiles_dir):
        for f in files:
            if f.endswith(".whl"):
                return os.path.join(root, f)
    return None


def wheel_entries(whl_path):
    """Return the set of file paths inside the wheel zip."""
    with zipfile.ZipFile(whl_path, "r") as zf:
        return set(zf.namelist())


def has_match(entries, pattern):
    """Check if any entry matches the given glob pattern."""
    return any(fnmatch.fnmatch(e, pattern) for e in entries)


def matching(entries, pattern):
    """Return entries matching the given glob pattern."""
    return sorted(e for e in entries if fnmatch.fnmatch(e, pattern))


# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

failures = []


def assert_has(entries, pattern, description):
    """Assert at least one wheel entry matches the pattern."""
    if not has_match(entries, pattern):
        failures.append(f"MISSING: {description} (pattern: {pattern})")
    else:
        print(f"  OK: {description}")


def assert_count_ge(entries, pattern, minimum, description):
    """Assert at least `minimum` entries match the pattern."""
    found = matching(entries, pattern)
    if len(found) < minimum:
        failures.append(
            f"TOO FEW: {description} — expected >= {minimum}, got {len(found)} "
            f"(pattern: {pattern})"
        )
    else:
        print(f"  OK: {description} ({len(found)} files)")


def assert_none(entries, pattern, description):
    """Assert zero entries match the pattern."""
    found = matching(entries, pattern)
    if found:
        examples = found[:5]
        failures.append(
            f"UNEXPECTED: {description} — found {len(found)} files "
            f"(pattern: {pattern}), e.g. {examples}"
        )
    else:
        print(f"  OK: {description}")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_python_packages(entries):
    """All expected Python packages are present."""
    print("\n--- Python packages ---")
    assert_has(entries, "ttnn/__init__.py", "ttnn package")
    assert_has(entries, "tt_lib/__init__.py", "tt_lib package")
    assert_has(entries, "tracy/__init__.py", "tracy package")
    assert_has(entries, "triage/__init__.py", "triage package")


def test_native_extension(entries):
    """The _ttnn.so nanobind extension is included."""
    print("\n--- Native extension ---")
    assert_has(entries, "ttnn/_ttnn.so", "_ttnn.so extension module")


def test_runtime_firmware(entries):
    """Firmware binaries for all chip architectures."""
    print("\n--- Runtime firmware ---")
    for arch in ("wormhole", "blackhole", "quasar"):
        assert_count_ge(
            entries,
            f"ttnn/runtime/hw/lib/{arch}/*.o",
            1,
            f"{arch} firmware objects",
        )
    # Linker scripts
    for arch in ("wormhole", "blackhole", "quasar"):
        assert_count_ge(
            entries,
            f"ttnn/runtime/hw/toolchain/{arch}/*.ld",
            1,
            f"{arch} linker scripts",
        )


def test_tt_metal_data(entries):
    """tt_metal device descriptors and dispatch kernels."""
    print("\n--- tt_metal data ---")
    assert_count_ge(
        entries,
        "ttnn/tt_metal/soc_descriptors/*.yaml",
        1,
        "SOC descriptors",
    )
    assert_count_ge(
        entries,
        "ttnn/tt_metal/core_descriptors/*.yaml",
        1,
        "core descriptors",
    )
    # Dispatch kernel sources (shipped for JIT compilation)
    assert_count_ge(
        entries,
        "ttnn/tt_metal/kernels/*",
        1,
        "dispatch kernels",
    )


def test_jit_headers(entries):
    """JIT compilation headers for device kernels."""
    print("\n--- JIT headers ---")
    assert_count_ge(
        entries,
        "ttnn/ttnn/cpp/ttnn/operations/*/device/kernels/*.cpp",
        1,
        "operation device kernels",
    )


def test_no_test_files(entries):
    """No test files should be shipped in the wheel."""
    print("\n--- No test files ---")
    # Files inside any tests/ directory are never needed at runtime
    assert_none(entries, "*/tests/*", "files in tests/ subdirectories")
    assert_none(entries, "tests/*", "top-level tests/ directory")


def test_wheel_metadata(entries):
    """Standard wheel metadata files exist."""
    print("\n--- Wheel metadata ---")
    assert_has(entries, "ttnn-*.dist-info/METADATA", "METADATA")
    assert_has(entries, "ttnn-*.dist-info/WHEEL", "WHEEL")
    assert_has(entries, "ttnn-*.dist-info/RECORD", "RECORD")
    assert_has(entries, "ttnn-*.dist-info/entry_points.txt", "entry_points.txt")
    assert_has(entries, "ttnn-*.dist-info/LICENSE", "LICENSE")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    # Find the wheel in runfiles
    runfiles_dir = os.environ.get("RUNFILES_DIR") or os.path.join(
        os.path.dirname(os.path.abspath(sys.argv[0])), "..", ".."
    )
    whl_path = find_wheel(runfiles_dir)
    if not whl_path:
        print("ERROR: Could not find .whl file in runfiles", file=sys.stderr)
        sys.exit(1)

    print(f"Validating wheel: {os.path.basename(whl_path)}")
    entries = wheel_entries(whl_path)
    print(f"Total entries: {len(entries)}")

    test_python_packages(entries)
    test_native_extension(entries)
    test_runtime_firmware(entries)
    test_tt_metal_data(entries)
    test_jit_headers(entries)
    test_no_test_files(entries)
    test_wheel_metadata(entries)

    if failures:
        print(f"\n=== FAILED ({len(failures)} issues) ===")
        for f in failures:
            print(f"  {f}")
        sys.exit(1)
    else:
        print("\n=== ALL CHECKS PASSED ===")


if __name__ == "__main__":
    main()
