# Building tt-metal with Bazel

This document covers the Bazel build system for tt-metal. The project maintains
dual build systems (CMake and Bazel). CMake is the production default; Bazel
provides hermetic builds, fine-grained caching, and per-test affected-target
analysis.

## Quick Start

```bash
# Build everything (no hardware required)
bazel build ...

# Run CPU-only tests (no Tenstorrent hardware needed)
bazel test ...

# Run all tests on a Wormhole B0 machine
bazel test --config=wormhole_b0 ...

# Build a single target
bazel build //tt_metal
```

No system compiler is required — Bazel downloads a hermetic Clang 20 toolchain
automatically.

## Hardware Test Configurations

By default, `bazel test ...` excludes all tests that require Tenstorrent
hardware. This keeps the command useful on CPU-only machines (dev laptops,
CI build nodes). Use `--config=<name>` to include hardware tests:

| Config | Hardware | `ARCH_NAME` | Description |
|---|---|---|---|
| *(default)* | None | — | CPU-only tests (~2 targets) |
| `--config=wormhole_b0` | Wormhole B0 | `wormhole_b0` | Single-card WH tests |
| `--config=blackhole` | Blackhole | `blackhole` | Single-card BH tests |
| `--config=n150` | N150 | `wormhole_b0` | 1-chip Wormhole system |
| `--config=n300` | N300 | `wormhole_b0` | 2-chip Wormhole system |
| `--config=t3000` | T3000 | `wormhole_b0` | 8-chip Wormhole system |
| `--config=galaxy` | Galaxy | `wormhole_b0` | 32+ chip Wormhole system |

Each `--config` clears the default tag filter and sets the `ARCH_NAME`
environment variable for the test runner. Configs can be combined with other
flags:

```bash
# Run Wormhole tests in debug mode
bazel test --config=wormhole_b0 --config=debug //tests/tt_metal/...

# Run Blackhole tests with ASan
bazel test --config=blackhole --config=asan //tests/ttnn/...
```

### Hardware Tags

Tests declare their hardware requirements via Bazel tags:

| Tag | Meaning |
|---|---|
| `requires_wormhole_b0` | Needs a Wormhole B0 ASIC |
| `requires_blackhole` | Needs a Blackhole ASIC |
| `requires_multi_device` | Needs 2+ connected devices |
| `requires_N150` | Needs an N150 system |
| `requires_N300` | Needs an N300 system |
| `requires_T3000` | Needs a T3000 (8-chip) system |
| `requires_galaxy` | Needs a Galaxy (32+ chip) system |
| `host_only` | Explicitly marked as CPU-only (no hardware) |

## Build Configurations

### Build Types

| Config | Optimization | Debug Info | Notes |
|---|---|---|---|
| *(default)* | System default | — | Fast iteration |
| `--config=debug` | `-O0` | Full (`-g3`) | Mirrors `CMAKE_BUILD_TYPE=Debug` |
| `--config=relwithdebinfo` | `-O3` | Standard (`-g`) | Mirrors CMake default |
| `--config=release` | `-O3` | None | Enables `--stamp` |

### Sanitizers

| Config | Sanitizers | Notes |
|---|---|---|
| `--config=asan` | ASan + LSan + UBSan | Based on relwithdebinfo |
| `--config=tsan` | Thread Sanitizer | Uses `-O1` for accuracy |
| `--config=coverage` | LLVM source-based | Profile + coverage mapping |
| `--config=asan-coverage` | ASan + coverage | Combined |

### C++ Toolchains

| Config | Compiler | Stdlib | Source |
|---|---|---|---|
| *(default)* | Clang 20 | libc++ | Hermetic (auto-downloaded) |
| `--config=clang20-libcpp` | Clang 20 | libc++ | Hermetic (explicit) |
| `--config=clang20-libstdcpp` | Clang 20 | libstdc++ | Hermetic |
| `--config=gcc12` | GCC 12 | libstdc++ | System |
| `--config=gcc14` | GCC 14 | libstdc++ | System |

### Feature Flags

| Config | Description |
|---|---|
| `--config=tracy` | Enable Tracy profiler |
| `--config=code-timers` | Enable code timing instrumentation |
| `--config=light-metal-trace` | Enable Light Metal Trace |
| `--config=logging` | Enable verbose spdlog logging |
| `--config=distributed` | Enable MPI multi-host support |
| `--config=lto` | Enable thin LTO linking |
| `--config=clang-tidy` | Run clang-tidy static analysis |

### CI / Remote Cache

| Config | Description |
|---|---|
| `--config=ci` | Read/write BuildBuddy remote cache |
| `--config=ci-readonly` | Read-only remote cache (untrusted builds) |

CI must pass the API key: `--remote_header=x-buildbuddy-api-key="$KEY"`

### SFPI Cross-Compilation

For building firmware for Tenstorrent RISC-V cores:

| Config | Target | CPU Flag |
|---|---|---|
| `--config=sfpi-wormhole` | Wormhole RISC-V | `-mcpu=tt-wh` |
| `--config=sfpi-blackhole` | Blackhole RISC-V | `-mcpu=tt-bh` |
| `--config=sfpi-quasar32` | Quasar 32-bit (TRISC) | `-mcpu=tt-qsr32` |
| `--config=sfpi-quasar64` | Quasar 64-bit (DM) | `-mcpu=tt-qsr64` |

## Project Structure

### Key Bazel Files

| Path | Purpose |
|---|---|
| `MODULE.bazel` | Module definition + BCR dependencies |
| `extensions.bzl` | Non-BCR third-party deps (`http_archive`) |
| `.bazelrc` | Build/test configs and environment passthrough |
| `.bazelrc.user` | Local overrides (not checked in) |
| `bazel/pytest.bzl` | `pytest_test` / `pytest_suite` macros |
| `bazel/pytest_wrapper.py` | pytest entry point for Bazel sandboxed tests |
| `toolchain/` | Host C++ toolchain configs (GCC, Clang) |
| `toolchain/clang/` | Hermetic Clang 20 toolchain + downloader |
| `toolchain/sfpi/` | SFPI RISC-V cross-compilation toolchain |

### Major Build Targets

| Target | Description |
|---|---|
| `//tt_metal` | Core TT-Metal C++ library |
| `//ttnn:ttnn_core` | TTNN C++ library |
| `//ttnn:all_operations` | All TTNN operation implementations |
| `//ttnn/ttnn:ttnn_py` | Python `ttnn` package |
| `//tests/tt_metal/...` | C++ tt_metal tests |
| `//tests/ttnn/...` | C++ and Python TTNN tests |
| `//packaging:...` | Debian packages (tagged `manual`) |
| `//docs:html_tt_metalium` | Sphinx HTML docs |

### Test Organization

Tests live under `//tests/` and are organized to mirror the CMake layout:

```
tests/
├── tt_metal/
│   ├── tt_metal/          # C++ gtest: api, dispatch, device, data_movement, ...
│   └── tt_fabric/         # C++ gtest: fabric tests
└── ttnn/
    ├── unit_tests/        # Python pytest: op-level tests (one target per file)
    ├── lab_examples/      # C++ gtest: educational examples
    ├── tracy/cpp/         # C++ gtest: profiler tests
    └── python_api_testing/# Python pytest: legacy sweep/unit tests
```

Each Python test file becomes its own Bazel target via the `pytest_suite` macro,
enabling fine-grained affected-target analysis.

## Writing BUILD Files

### C++ Tests

```python
load("@rules_cc//cc:cc_test.bzl", "cc_test")

cc_test(
    name = "test_my_feature",
    srcs = ["test_my_feature.cpp"],
    deps = [
        "//tests:test_common_libs",
        "//ttnn:all_operations",
    ],
    tags = ["unit", "ttnn", "requires_wormhole_b0", "requires_blackhole"],
)
```

Always include appropriate `requires_*` tags if the test opens a device.

### Python Tests

```python
load("//bazel:pytest.bzl", "pytest_suite")

pytest_suite(
    name = "my_tests",
    srcs = glob(["test_*.py"]),
    deps = ["//ttnn/ttnn:ttnn_py"],
    markers = ["requires_wormhole_b0"],
)
```

The `markers` field maps pytest markers to Bazel tags automatically.

### Common Gotchas

1. **`glob()` stops at subpackage boundaries.** If a directory has its own
   `BUILD.bazel`, parent globs won't see its files. Use explicit deps instead.

2. **`copts` are not transitive.** If your test needs `-isystem .` for
   repo-root includes, declare it on the `cc_test`, not just on a library dep.

3. **Firmware targets need platform constraints.** Use
   `target_compatible_with = ["@platforms//cpu:riscv32"]` on RISC-V-only
   targets to prevent host compilation.

4. **Host-specific compiler flags belong in toolchain configs,** not in
   `.bazelrc`. Putting `-march=x86-64-v3` in `.bazelrc` would break SFPI
   RISC-V cross-compilation.

## Differences from CMake

| Aspect | CMake | Bazel |
|---|---|---|
| Toolchain | System compiler | Hermetic Clang 20 (downloaded) |
| GoogleTest version | 1.13.0 | 1.15.2 |
| Unity builds | Yes (~208 units) | No (1,122 individual files) |
| Precompiled headers | Yes | No |
| Remote cache | ccache + Redis | BuildBuddy (gRPC) |
| Python wheel | 5 shared libs | 1 monolithic `_ttnn.so` (230MB) |
| Test granularity | Suite-level | Per-file targets |
| Single-file rebuild | ~63s | ~13s |
| Header change rebuild | ~62-286s | ~362-2495s |

Bazel's per-file test granularity enables affected-target CI (only run tests
whose transitive deps changed). CMake's unity builds give faster full rebuilds
when widely-included headers change.

## Local Overrides

Create `.bazelrc.user` (gitignored) for local settings:

```
# Use system GCC instead of hermetic Clang
build --config=gcc14

# Point to a local remote cache
build --remote_cache=grpc://localhost:9092

# Always run with Wormhole hardware
test --config=wormhole_b0
```

## Useful Commands

```bash
# List all test targets
bazel query 'kind(".*_test rule", //tests/...)'

# Find tests that can run without hardware
bazel query 'kind(".*_test rule", //tests/...) except attr(tags, "requires_", kind(".*_test rule", //tests/..."))'

# Show what a target depends on
bazel query 'deps(//ttnn:ttnn_core)' --output=graph

# Build with verbose compilation commands
bazel build --subcommands //tt_metal

# Run a specific test with output
bazel test --test_output=streamed //tests/tt_metal/tt_metal:hal_codegen_test
```
