"""C++ toolchain configurations matching CMake toolchain files.

Each toolchain mirrors the corresponding cmake/*-toolchain.cmake file plus
the global flags from CMakeLists.txt lines 166-192 and cmake/linking.cmake.
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
    # Compressed debug sections (matches linking.cmake zlib compression)
    "-gz",
]

_CLANG_COMPILE_FLAGS = [
    "-Wconditional-uninitialized",
    "-Xclang",
    "-fno-pch-timestamp",
]

_CLANG_LIBCPP_COMPILE_FLAGS = [
    "-stdlib=libc++",
]

_CLANG_LIBSTDCPP_COMPILE_FLAGS = [
    "-fsized-deallocation",
]

_CLANG_LIBCPP_LINK_FLAGS = [
    "-lc++",
    "-lc++abi",
]

_GCC_COMPILE_FLAGS = [
    "-fpch-preprocess",
    "-fsized-deallocation",
    "-Wno-array-bounds",
    "-Wno-deprecated",
    "-Wno-int-in-bool-context",
    "-Wno-maybe-uninitialized",
    "-Wno-non-template-friend",
    "-Wno-restrict",
    "-Wno-sign-compare",
    "-Wno-strict-aliasing",
    "-Wno-stringop-overflow",
    "-Wno-stringop-overread",
    "-Wno-unused-local-typedefs",
    "-Wno-pessimizing-move",
    "-Wno-dangling-reference",
    "-Wno-overloaded-virtual",
]

_COMMON_LINK_FLAGS = [
    "-lstdc++",
    "-lm",
    "-ldl",
    "-lpthread",
]

_COMMON_LINK_FLAGS_LIBCPP = [
    "-lm",
    "-ldl",
    "-lpthread",
]

# ---------------------------------------------------------------------------
# All C++ actions that receive compile flags
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
# Helper: build a feature for a list of flags
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

def _cc_toolchain_config_impl(ctx):
    compiler_id = ctx.attr.compiler     # "clang" or "gcc"
    compiler_ver = ctx.attr.compiler_version  # e.g. "20", "12", "14"
    stdlib = ctx.attr.stdlib            # "libc++" or "libstdc++"
    cc_path = ctx.attr.cc_path          # e.g. "/usr/bin/clang-20"
    cxx_path = ctx.attr.cxx_path        # e.g. "/usr/bin/clang++-20"
    linker_path = ctx.attr.linker_path  # e.g. "/usr/bin/ld.mold"

    tool_paths = [
        tool_path(name = "gcc", path = cxx_path),
        tool_path(name = "ld", path = linker_path),
        tool_path(name = "ar", path = "/usr/bin/ar"),
        tool_path(name = "cpp", path = "/usr/bin/cpp"),
        tool_path(name = "gcov", path = "/usr/bin/gcov"),
        tool_path(name = "nm", path = "/usr/bin/nm"),
        tool_path(name = "objcopy", path = "/usr/bin/objcopy"),
        tool_path(name = "objdump", path = "/usr/bin/objdump"),
        tool_path(name = "strip", path = "/usr/bin/strip"),
    ]

    features = []

    # Common compile flags for all compilers
    features.append(_make_flag_feature(
        "common_compile_flags",
        _ALL_COMPILE_ACTIONS,
        _COMMON_COMPILE_FLAGS,
    ))

    # Compiler-specific flags
    if compiler_id == "clang":
        features.append(_make_flag_feature(
            "clang_compile_flags",
            _ALL_CPP_COMPILE_ACTIONS,
            _CLANG_COMPILE_FLAGS,
        ))
        if stdlib == "libc++":
            features.append(_make_flag_feature(
                "libcpp_compile_flags",
                _ALL_CPP_COMPILE_ACTIONS,
                _CLANG_LIBCPP_COMPILE_FLAGS,
            ))
            features.append(_make_flag_feature(
                "libcpp_link_flags",
                _ALL_LINK_ACTIONS,
                _CLANG_LIBCPP_LINK_FLAGS + _COMMON_LINK_FLAGS_LIBCPP,
            ))
        else:
            features.append(_make_flag_feature(
                "libstdcpp_compile_flags",
                _ALL_CPP_COMPILE_ACTIONS,
                _CLANG_LIBSTDCPP_COMPILE_FLAGS,
            ))
            features.append(_make_flag_feature(
                "default_link_flags",
                _ALL_LINK_ACTIONS,
                _COMMON_LINK_FLAGS,
            ))
    elif compiler_id == "gcc":
        features.append(_make_flag_feature(
            "gcc_compile_flags",
            _ALL_CPP_COMPILE_ACTIONS,
            _GCC_COMPILE_FLAGS,
        ))
        features.append(_make_flag_feature(
            "default_link_flags",
            _ALL_LINK_ACTIONS,
            _COMMON_LINK_FLAGS,
        ))

    # Use the specified linker via -fuse-ld
    if linker_path:
        linker_basename = linker_path.rsplit("/", 1)[-1] if "/" in linker_path else linker_path

        # Map binary name to -fuse-ld value
        fuse_ld_value = None
        if "mold" in linker_basename:
            fuse_ld_value = "mold"
        elif "lld" in linker_basename:
            fuse_ld_value = "lld"

        if fuse_ld_value:
            features.append(_make_flag_feature(
                "linker_selection",
                _ALL_LINK_ACTIONS,
                ["-fuse-ld=" + fuse_ld_value],
            ))

    # Compressed debug sections (matches linking.cmake zlib compression)
    features.append(_make_flag_feature(
        "compress_debug_sections",
        _ALL_LINK_ACTIONS,
        ["-Wl,--compress-debug-sections=zlib"],
    ))

    # Supports dynamic linking
    features.append(feature(name = "supports_dynamic_linker", enabled = True))
    features.append(feature(name = "supports_pic", enabled = True))

    toolchain_identifier = "{compiler}{ver}-{stdlib}".format(
        compiler = compiler_id,
        ver = compiler_ver,
        stdlib = stdlib.replace("++", "pp"),
    )

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = features,
        toolchain_identifier = toolchain_identifier,
        host_system_name = "x86_64-unknown-linux-gnu",
        target_system_name = "x86_64-unknown-linux-gnu",
        target_cpu = "x86_64",
        target_libc = "glibc",
        compiler = compiler_id + "-" + compiler_ver,
        abi_version = stdlib,
        abi_libc_version = "glibc",
        tool_paths = tool_paths,
        cxx_builtin_include_directories = ctx.attr.cxx_builtin_include_directories,
    )

cc_toolchain_config = rule(
    implementation = _cc_toolchain_config_impl,
    attrs = {
        "compiler": attr.string(mandatory = True, values = ["clang", "gcc"]),
        "compiler_version": attr.string(mandatory = True),
        "stdlib": attr.string(mandatory = True, values = ["libc++", "libstdc++"]),
        "cc_path": attr.string(mandatory = True),
        "cxx_path": attr.string(mandatory = True),
        "linker_path": attr.string(default = "/usr/bin/ld"),
        "cxx_builtin_include_directories": attr.string_list(default = []),
    },
    provides = [CcToolchainConfigInfo],
)
