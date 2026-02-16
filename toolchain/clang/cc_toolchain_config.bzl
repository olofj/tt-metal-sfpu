"""Hermetic Clang 20 toolchain configuration.

This file is symlinked into the @llvm_clang repository by the repository
rule so that tool_path references resolve relative to the downloaded
LLVM binaries.  It replicates the flags from toolchain/cc_toolchain_config.bzl
but uses the bundled LLD linker instead of system mold.

Compiler flags match CMakeLists.txt lines 166-192 and cmake/linking.cmake.
"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load(
    "@rules_cc//cc:cc_toolchain_config_lib.bzl",
    "feature",
    "flag_group",
    "flag_set",
    "tool_path",
)

# ---------------------------------------------------------------------------
# Shared flag constants (from CMakeLists.txt lines 166-192)
# ---------------------------------------------------------------------------

_COMMON_COMPILE_FLAGS = [
    "-march=x86-64-v3",
    "-fPIC",
    "-pipe",
    "-fvisibility-inlines-hidden",
    "-Wall",
    "-Werror",
    "-Wno-deprecated-declarations",
    "-std=c++20",
    "-no-canonical-prefixes",
]

_CLANG_COMPILE_FLAGS = [
    "-Wconditional-uninitialized",
    "-Xclang",
    "-fno-pch-timestamp",
]

_LIBCPP_COMPILE_FLAGS = [
    "-stdlib=libc++",
]

_LIBSTDCPP_COMPILE_FLAGS = [
    "-fsized-deallocation",
]

_LIBCPP_LINK_FLAGS = [
    # Statically link libc++ and libc++abi so exec-config binaries
    # (capnpc, flatc, protoc) can run without needing libc++.so in
    # LD_LIBRARY_PATH. The hermetic toolchain bundles both static
    # and shared libraries; static linking is more portable for tools.
    "-Wl,-Bstatic",
    "-lc++",
    "-lc++abi",
    "-Wl,-Bdynamic",
    "-lm",
    "-ldl",
    "-lpthread",
]

_LIBSTDCPP_LINK_FLAGS = [
    "-lstdc++",
    "-lm",
    "-ldl",
    "-lpthread",
]

# ---------------------------------------------------------------------------
# Action lists
# ---------------------------------------------------------------------------

_ALL_COMPILE_ACTIONS = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.clif_match,
    ACTION_NAMES.lto_backend,
]

_ALL_CPP_COMPILE_ACTIONS = [
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.linkstamp_compile,
]

_ALL_LINK_ACTIONS = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _make_flag_feature(name, actions, flags):
    """Create a feature that applies flags to the given actions."""
    return feature(
        name = name,
        enabled = True,
        flag_sets = [
            flag_set(
                actions = actions,
                flag_groups = [
                    flag_group(flags = flags),
                ],
            ),
        ],
    )

# ---------------------------------------------------------------------------
# Rule implementation
# ---------------------------------------------------------------------------

def _clang_cc_toolchain_config_impl(ctx):
    stdlib = ctx.attr.stdlib  # "libc++" or "libstdc++"

    # Tool paths are relative to the package containing this rule.
    # When symlinked into @llvm_clang, these resolve to the downloaded binaries.
    tool_paths = [
        tool_path(name = "gcc", path = "bin/clang++"),
        tool_path(name = "ld", path = "bin/ld.lld"),
        tool_path(name = "ar", path = "bin/llvm-ar"),
        tool_path(name = "cpp", path = "bin/clang-cpp"),
        tool_path(name = "gcov", path = "bin/llvm-cov"),
        tool_path(name = "nm", path = "bin/llvm-nm"),
        tool_path(name = "objcopy", path = "bin/llvm-objcopy"),
        tool_path(name = "objdump", path = "bin/llvm-objdump"),
        tool_path(name = "strip", path = "bin/llvm-strip"),
    ]

    features = []

    # Common compile flags
    features.append(_make_flag_feature(
        "common_compile_flags",
        _ALL_COMPILE_ACTIONS,
        _COMMON_COMPILE_FLAGS,
    ))

    # Clang-specific compile flags
    features.append(_make_flag_feature(
        "clang_compile_flags",
        _ALL_CPP_COMPILE_ACTIONS,
        _CLANG_COMPILE_FLAGS,
    ))

    # stdlib-specific flags
    if stdlib == "libc++":
        features.append(_make_flag_feature(
            "libcpp_compile_flags",
            _ALL_CPP_COMPILE_ACTIONS,
            _LIBCPP_COMPILE_FLAGS,
        ))
        features.append(_make_flag_feature(
            "libcpp_link_flags",
            _ALL_LINK_ACTIONS,
            _LIBCPP_LINK_FLAGS,
        ))
    else:
        features.append(_make_flag_feature(
            "libstdcpp_compile_flags",
            _ALL_CPP_COMPILE_ACTIONS,
            _LIBSTDCPP_COMPILE_FLAGS,
        ))
        features.append(_make_flag_feature(
            "default_link_flags",
            _ALL_LINK_ACTIONS,
            _LIBSTDCPP_LINK_FLAGS,
        ))

    # Use bundled LLD
    features.append(_make_flag_feature(
        "linker_selection",
        _ALL_LINK_ACTIONS,
        ["-fuse-ld=lld"],
    ))

    features.append(feature(name = "supports_dynamic_linker", enabled = True))
    features.append(feature(name = "supports_pic", enabled = True))

    stdlib_label = stdlib.replace("++", "pp")
    toolchain_identifier = "clang20-{stdlib}".format(stdlib = stdlib_label)

    # Include directories within the downloaded toolchain.
    # For libc++: headers are bundled in include/c++/v1.
    # For libstdc++: we need the system GCC headers (not hermetic for that part).
    if stdlib == "libc++":
        cxx_builtin_include_directories = [
            "include/c++/v1",
            "include/x86_64-unknown-linux-gnu/c++/v1",
            "lib/clang/20/include",
            # System libc headers are still needed (glibc is not bundled).
            "/usr/include",
            "/usr/include/x86_64-linux-gnu",
        ]
    else:
        cxx_builtin_include_directories = [
            # libstdc++ headers come from the system GCC installation.
            "/usr/include/c++/14",
            "/usr/include/x86_64-linux-gnu/c++/14",
            "lib/clang/20/include",
            "/usr/include",
            "/usr/include/x86_64-linux-gnu",
        ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = features,
        toolchain_identifier = toolchain_identifier,
        host_system_name = "x86_64-unknown-linux-gnu",
        target_system_name = "x86_64-unknown-linux-gnu",
        target_cpu = "x86_64",
        target_libc = "glibc",
        compiler = "clang-20",
        abi_version = stdlib,
        abi_libc_version = "glibc",
        tool_paths = tool_paths,
        cxx_builtin_include_directories = cxx_builtin_include_directories,
    )

clang_cc_toolchain_config = rule(
    implementation = _clang_cc_toolchain_config_impl,
    attrs = {
        "stdlib": attr.string(
            mandatory = True,
            values = ["libc++", "libstdc++"],
            doc = "C++ standard library: 'libc++' (bundled) or 'libstdc++' (system).",
        ),
    },
    provides = [CcToolchainConfigInfo],
)
