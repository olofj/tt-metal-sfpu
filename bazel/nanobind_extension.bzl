"""Bazel macro for building nanobind Python extension modules.

Produces a shared object (.so) loadable by Python's import machinery.
Replaces the CMake add_library(ttnn SHARED) + nanobind_*() helper calls
defined in ttnn/CMakeLists.txt lines 729-847.

Usage:
    load("//bazel:nanobind_extension.bzl", "nanobind_extension")

    nanobind_extension(
        name = "_ttnn",
        srcs = [...],
        deps = ["//ttnn:ttnn_core", ...],
    )

This generates:
    - :_ttnn.so  — shared object loadable via `import _ttnn`
"""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")

def nanobind_extension(
        name,
        srcs,
        deps = [],
        hdrs = [],
        copts = [],
        linkopts = [],
        visibility = None,
        **kwargs):
    """Build a nanobind Python extension module as a shared library.

    The output is a .so file with the PyInit_{name} entry point that
    Python can load via `import {name}`. Uses linkshared=True to produce
    a shared object from cc_binary (Bazel's native mechanism for building
    .so files that are not cc_library outputs).

    Args:
        name: Module name. The output will be {name}.so (e.g., _ttnn.so).
        srcs: C++ source files containing nanobind bindings.
        deps: cc_library dependencies (TTNN C++ lib, tt_metal, etc.).
        hdrs: Header files for the extension module.
        copts: Additional compiler options.
        linkopts: Additional linker options.
        visibility: Bazel visibility specification.
        **kwargs: Passed through to cc_binary.
    """
    cc_binary(
        name = name + ".so",
        srcs = srcs + hdrs,
        deps = deps + [
            "@nanobind",
            "@rules_python//python/cc:current_py_cc_headers",
        ],
        copts = copts + [
            # Note: -fvisibility=hidden is intentionally NOT used here.
            # nanobind recommends it for single-module builds, but the split
            # module architecture (core + per-operation .so files) requires
            # RTTI typeinfo symbols to be shared across DSOs via RTLD_GLOBAL.
            # Hidden visibility prevents typeinfo export, causing:
            #   - std::bad_cast in nb::cast() (pool, experimental modules)
            #   - HostBuffer::view_as() type_info mismatch (conv modules)
            "-Os",  # nanobind_opt_size() equivalent
            "-Wno-attributes",  # GCC visibility mismatch warnings (CMake: -Wno-attributes)
        ],
        linkopts = linkopts + [
            # nanobind_link_options() equivalent: allow undefined symbols
            # at link time — they resolve when Python loads the .so.
            "-Wl,--no-as-needed",
        ],
        linkshared = True,
        visibility = visibility,
        **kwargs
    )
