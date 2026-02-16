"""Bazel macro for defining TTNN operation libraries.

Each TTNN operation follows an identical CMake pattern: a cc_library that
links against TTNN::Core (public) and TT::Metalium (private), globs
device/kernels/* as shipped-but-not-compiled headers, and uses standard
include paths rooted at ttnn/cpp/.

This macro encapsulates that pattern so individual BUILD.bazel files
only need to list their sources and headers.

Usage:
    load("//ttnn/bazel:ttnn_operation.bzl", "ttnn_operation")

    ttnn_operation(
        name = "matmul",
        srcs = ["matmul.cpp", "device/matmul_device_operation.cpp", ...],
        hdrs = ["matmul.hpp", "device/matmul_device_operation.hpp", ...],
    )

This generates two targets:
    - :matmul       — full cc_library (srcs + hdrs, all deps)
    - :matmul_hdrs  — header-only cc_library (hdrs only)

The _hdrs target exists to break circular dependencies between operations.
In CMake, all operations share an include path to ttnn/cpp/ and can include
each other's headers freely. In Bazel, cross-operation header includes must
be declared as explicit dependencies. When operation A's headers reference
operation B's headers (and vice versa), they can depend on each other's
_hdrs targets without creating a cycle.
"""

load("@rules_cc//cc:cc_library.bzl", "cc_library")

def ttnn_operation(
        name,
        srcs,
        hdrs = [],
        kernel_hdrs = None,
        extra_deps = [],
        extra_hdrs_deps = [],
        extra_copts = [],
        visibility = None):
    """Creates cc_library targets for a single TTNN operation.

    Generates two targets:
      - {name}: Full library with sources, headers, and all dependencies.
      - {name}_hdrs: Header-only library for breaking circular cross-operation deps.

    Mirrors the CMake pattern used by every ttnn/cpp/ttnn/operations/*/CMakeLists.txt:
      - Links TTNN::Core as a public dep (headers depend on it)
      - Links TT::Metalium as a private/implementation dep
      - Globs device/kernels/** for kernel headers shipped to the device at runtime
      - Sets standard copts (-Wno-c++11-narrowing, -Wno-unused-lambda-capture)

    Args:
        name: Target name, should match the operation directory name.
        srcs: C++ source files (.cpp) for this operation.
        hdrs: Public API header files (.hpp/.h) for this operation.
        kernel_hdrs: Device kernel files. If None, globs device/kernels/**.
            These are HEADERS in CMake (FILE_SET kernels) — they are shipped
            to the device for JIT compilation, not compiled by the host compiler.
        extra_deps: Additional dependencies beyond TTNN::Core + TT::Metalium
            for the full library target. Use this for cross-operation deps
            needed by .cpp files.
        extra_hdrs_deps: Additional dependencies for the header-only target.
            Use this when this operation's headers include another operation's
            headers (e.g., binary.hpp includes unary_op_types.hpp).
        extra_copts: Additional compiler options beyond the standard set.
        visibility: Bazel visibility. Defaults to //ttnn package and subpackages.
    """
    _visibility = visibility or ["//ttnn:__subpackages__"]

    if kernel_hdrs == None:
        kernel_hdrs = native.glob(
            ["device/kernels/**"],
            allow_empty = True,
        )

    # Header-only target: provides just the public API headers.
    # Used by other operations that need to include this operation's headers
    # without taking a full link dependency (and avoiding circular deps).
    cc_library(
        name = name + "_hdrs",
        hdrs = hdrs + kernel_hdrs,
        includes = ["."],
        visibility = _visibility,
        deps = [
            "//ttnn:ttnn_core",
        ] + extra_hdrs_deps,
    )

    # Full library target: compiles sources and links against all deps.
    cc_library(
        name = name,
        srcs = srcs,
        copts = [
            # Match CMake: suppress warnings that are globally set for TTNN
            "-Wno-c++11-narrowing",
            "-Wno-unused-lambda-capture",
        ] + extra_copts,
        visibility = _visibility,
        deps = [
            ":" + name + "_hdrs",
        ] + extra_deps,
        # TT::Metalium — private dep in CMake (only linked, not exposed in headers).
        # implementation_deps prevents header leakage to downstream targets.
        implementation_deps = [
            "//tt_metal:tt_metal",
        ],
    )
