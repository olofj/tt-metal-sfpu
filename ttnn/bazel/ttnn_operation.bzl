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
        hdrs = glob(["**/*.hpp", "**/*.h"], exclude=["device/kernels/**"], allow_empty=True),
    )

This generates three targets:
    - :matmul         — full cc_library (srcs + hdrs, all deps)
    - :matmul_hdrs    — header-only cc_library (hdrs only, NO deps on ttnn_core)
    - :nanobind_srcs  — filegroup of *_nanobind.cpp files for the _ttnn extension

The _hdrs target is deliberately dependency-free (beyond extra_hdrs_deps for
cross-operation headers). This allows:
  1. ttnn_core to depend on operation _hdrs targets without circular deps
  2. Other operations to depend on _hdrs to break circular compile deps

The _nanobind_srcs target exports nanobind binding source files so the _ttnn
Python extension module (built from //ttnn:BUILD.bazel) can compile them.
These files are NOT compiled into the operation library itself — they are
only compiled as part of the Python extension, matching CMake's separate
TTNN_SRC_PYBIND / CCL_TTNN_SRCS_PYBIND source lists.
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

    Generates three targets:
      - {name}: Full library with sources, headers, and all dependencies.
      - {name}_hdrs: Header-only library with NO ttnn_core dep (breaks cycles).
      - nanobind_srcs: Filegroup of *_nanobind.cpp for the _ttnn extension.

    Args:
        name: Target name, should match the operation directory name.
        srcs: C++ source files (.cpp) for this operation.
        hdrs: Public API header files (.hpp/.h) for this operation.
            Use glob(["**/*.hpp", "**/*.h"], exclude=["device/kernels/**"])
            for operations with default kernel paths.
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
    # Deliberately has NO dep on //ttnn:ttnn_core to avoid circular deps.
    # ttnn_core itself depends on some operation _hdrs targets because
    # core files include operation headers (a legacy pattern from CMake's
    # broad include paths). If _hdrs depended on ttnn_core, this would cycle.
    cc_library(
        name = name + "_hdrs",
        hdrs = hdrs + kernel_hdrs,
        includes = ["."],
        visibility = _visibility,
        deps = extra_hdrs_deps,
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
            "//ttnn:ttnn_core",
        ] + extra_deps,
        # TT::Metalium — private dep in CMake (only linked, not exposed in headers).
        # implementation_deps prevents header leakage to downstream targets.
        implementation_deps = [
            "//tt_metal:tt_metal",
        ],
    )

    # Nanobind binding sources: exported for the _ttnn Python extension module.
    # These *_nanobind.cpp files are NOT compiled into the operation library —
    # they are only compiled as part of //ttnn:_ttnn.so.
    # Uses a fixed name "nanobind_srcs" (not prefixed with operation name) so
    # the _ttnn BUILD target can reference them uniformly as pkg:nanobind_srcs.
    native.filegroup(
        name = "nanobind_srcs",
        srcs = native.glob(
            ["**/*_nanobind.cpp"],
            allow_empty = True,
        ),
        visibility = _visibility,
    )
