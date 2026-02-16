"""SFPI RISC-V cross-compiler toolchain configuration.

Defines a cc_toolchain_config rule for the Tenstorrent SFPI compiler,
which targets custom RISC-V cores (Wormhole, Blackhole, Quasar).

This file is symlinked into the @sfpi repository by the repository rule
so that tool_path references resolve relative to the downloaded binaries.

Compiler flags are derived from:
  - tt_metal/hw/CMakeLists.txt (GPP_FLAGS_common, GPP_FLAGS_{arch})
  - tt_metal/jit_build/build.cpp (JitBuildEnv::init)
  - tt_metal/llrt/hal/tt-*/*.cpp (per-arch -mcpu flags)
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
# Compiler flags from tt_metal/hw/CMakeLists.txt (GPP_FLAGS_common)
# and tt_metal/jit_build/build.cpp (JitBuildEnv::init)
# ---------------------------------------------------------------------------

_COMMON_COMPILE_FLAGS = [
    "-std=c++17",
    "-flto=auto",
    "-ffast-math",
    "-fno-use-cxa-atexit",
    "-fno-exceptions",
    "-Wall",
    "-Werror",
    "-Wno-deprecated-declarations",
    "-Wno-unknown-pragmas",
    "-Wno-error=multistatement-macros",
    "-Wno-error=parentheses",
    "-Wno-error=unused-but-set-variable",
    "-Wno-unused-variable",
    "-Wno-unused-function",
    "-Os",
    "-fno-tree-loop-distribute-patterns",
]

_COMMON_LINK_FLAGS = [
    "-flto=auto",
    "-ffast-math",
    "-fno-exceptions",
    "-nostdlib",
]

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

_ALL_COMPILE_ACTIONS = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
]

_ALL_LINK_ACTIONS = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

# ---------------------------------------------------------------------------
# Helpers
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

def _sfpi_cc_toolchain_config_impl(ctx):
    mcpu = ctx.attr.mcpu

    # Tool paths are relative to the package containing this rule.
    # When symlinked into @sfpi, these resolve to the downloaded binaries.
    tool_paths = [
        tool_path(name = "gcc", path = "compiler/bin/riscv-tt-elf-g++"),
        tool_path(name = "ld", path = "compiler/bin/riscv-tt-elf-ld"),
        tool_path(name = "ar", path = "compiler/bin/riscv-tt-elf-ar"),
        tool_path(name = "cpp", path = "compiler/bin/riscv-tt-elf-gcc"),
        tool_path(name = "gcov", path = "/bin/false"),
        tool_path(name = "nm", path = "compiler/bin/riscv-tt-elf-nm"),
        tool_path(name = "objcopy", path = "compiler/bin/riscv-tt-elf-objcopy"),
        tool_path(name = "objdump", path = "compiler/bin/riscv-tt-elf-objdump"),
        tool_path(name = "strip", path = "compiler/bin/riscv-tt-elf-strip"),
    ]

    features = []

    # Architecture-specific CPU flag
    features.append(_make_flag_feature(
        "mcpu",
        _ALL_COMPILE_ACTIONS + _ALL_LINK_ACTIONS,
        ["-mcpu=" + mcpu],
    ))

    # Common compile flags
    features.append(_make_flag_feature(
        "common_compile_flags",
        _ALL_COMPILE_ACTIONS,
        _COMMON_COMPILE_FLAGS,
    ))

    # Common link flags
    features.append(_make_flag_feature(
        "common_link_flags",
        _ALL_LINK_ACTIONS,
        _COMMON_LINK_FLAGS,
    ))

    # Bare-metal: no shared libraries
    features.append(feature(name = "supports_dynamic_linker", enabled = False))
    features.append(feature(name = "supports_pic", enabled = False))

    toolchain_identifier = "sfpi-riscv-" + mcpu

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = features,
        toolchain_identifier = toolchain_identifier,
        host_system_name = "x86_64-unknown-linux-gnu",
        target_system_name = "riscv32-unknown-elf",
        target_cpu = "riscv32",
        target_libc = "none",
        compiler = "riscv-tt-elf-g++",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
        cxx_builtin_include_directories = [
            "compiler/riscv-tt-elf/include",
            "compiler/lib/gcc/riscv-tt-elf",
            "include",
        ],
    )

sfpi_cc_toolchain_config = rule(
    implementation = _sfpi_cc_toolchain_config_impl,
    attrs = {
        "mcpu": attr.string(
            mandatory = True,
            doc = "RISC-V CPU target flag, e.g. 'tt-wh', 'tt-bh', 'tt-qsr32'.",
        ),
    },
    provides = [CcToolchainConfigInfo],
)
