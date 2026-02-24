load("@rules_cc//cc:cc_library.bzl", "cc_library")

# nanobind runtime library — stable ABI build targeting Python 3.12+.
#
# Mirrors CMake's nanobind_build_library("nanobind-static-abi3") which builds
# the nanobind runtime as a static library with Py_LIMITED_API enabled.
#
# Uses nb_combined.cpp (unity build) which #include's all other .cpp files
# in src/. This matches nanobind's default CMake behavior and is faster
# than compiling individual translation units.
#
# The defines match the CMake function nanobind_build_library() with the
# -static and -abi3 suffixes:
#   - NB_STATIC: build as static archive (linked into extension .so)
#   - Py_LIMITED_API=0x030C0000: target Python 3.12 stable ABI
#   - NB_ABORT_ON_LEAK: abort on reference leaks (matches CMake default)
#   - NB_DOMAIN=ttnn: isolate type bindings to avoid cross-extension conflicts
#   - NB_COMPACT_ASSERTIONS: smaller assertion messages for release builds
cc_library(
    name = "nanobind",
    # nb_combined.cpp is the unity build source — it #include's all other
    # .cpp files in src/. Those files plus .h files are listed as textual
    # headers so Bazel ships them to the sandbox.
    srcs = ["src/nb_combined.cpp"] + glob(["src/*.h"]),
    textual_hdrs = glob(
        ["src/*.cpp"],
        exclude = ["src/nb_combined.cpp"],
    ),
    hdrs = glob(["include/nanobind/**/*.h"]),
    copts = [
        "-fPIC",
        "-Os",  # nanobind_opt_size() equivalent
        # Note: -fvisibility=hidden is intentionally NOT used here.
        # nanobind recommends it for single-module builds, but the split
        # module architecture requires typeinfo symbols to be visible so
        # that nb::cast<T>() can resolve types registered by other modules.
    ],
    defines = [
        "NB_STATIC",
        "NB_ABORT_ON_LEAK",
        "NB_DOMAIN=ttnn",
        "NB_COMPACT_ASSERTIONS",
        "Py_LIMITED_API=0x030C0000",
    ],
    includes = [
        "include",
        "src",  # nb_combined.cpp #include's sibling .cpp files
    ],
    visibility = ["//visibility:public"],
    deps = [
        "@rules_python//python/cc:current_py_cc_headers",
        "@robin_map//:robin_map",
    ],
)
