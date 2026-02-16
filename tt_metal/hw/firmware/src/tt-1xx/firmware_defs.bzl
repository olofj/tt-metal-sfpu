"""Macros for generating firmware cross-compilation targets.

Each firmware binary links a single .cc source file with pre-compiled
support objects (crt0, noc, substitutes) and a preprocessed linker script
to produce a bare-metal RISC-V ELF.

This mirrors the JIT build flow in tt_metal/jit_build/build.cpp and the
HAL query interfaces in tt_metal/llrt/hal/tt-1xx/.

Build with:
    bazel build --config=sfpi-wormhole //tt_metal/hw/firmware/src/tt-1xx:all
    bazel build --config=sfpi-blackhole //tt_metal/hw/firmware/src/tt-1xx:all
"""

# ===================================================================
# Include paths matching tt_metal/hw/CMakeLists.txt (lines 353-380)
# and tt_metal/jit_build/build.cpp JitBuildEnv::init
# ===================================================================

_COMMON_INCLUDES = [
    "-Itt_metal",
    "-Itt_metal/api",
    "-Itt_metal/api/tt-metalium",
    "-Itt_metal/hw/inc",
    "-Itt_metal/hw/inc/debug",
    "-Itt_metal/hw/firmware/src/tt-1xx",
]

_ARCH_INCLUDES = {
    "wormhole": [
        "-Itt_metal/hw/inc/internal/tt-1xx/wormhole",
        "-Itt_metal/hw/inc/internal/tt-1xx/wormhole/wormhole_b0_defines",
        "-Itt_metal/hw/inc/internal/tt-1xx/wormhole/noc",
        "-Itt_metal/hw/ckernels/wormhole_b0/metal/common",
        "-Itt_metal/hw/ckernels/wormhole_b0/metal/llk_io",
        "-Itt_metal/third_party/tt_llk/tt_llk_wormhole_b0/common/inc",
        "-Itt_metal/third_party/tt_llk/tt_llk_wormhole_b0/llk_lib",
    ],
    "blackhole": [
        "-Itt_metal/hw/inc/internal/tt-1xx/blackhole",
        "-Itt_metal/hw/inc/internal/tt-1xx/blackhole/noc",
        "-Itt_metal/hw/ckernels/blackhole/metal/common",
        "-Itt_metal/hw/ckernels/blackhole/metal/llk_io",
        "-Itt_metal/third_party/tt_llk/tt_llk_blackhole/common/inc",
        "-Itt_metal/third_party/tt_llk/tt_llk_blackhole/llk_lib",
    ],
}

# Architecture-specific defines (from CMakeLists.txt line 296 + HAL)
_ARCH_DEFINES = {
    "wormhole": "-DARCH_WORMHOLE",
    "blackhole": "-DARCH_BLACKHOLE",
}

# Common compile flags from CMakeLists.txt GPP_FLAGS_common (lines 303-320)
# Note: -std=c++17, -mcpu, and -fno-tree-loop-distribute-patterns are
# already set by the SFPI toolchain config (cc_toolchain_config.bzl).
_FIRMWARE_COPTS = [
    "-DTENSIX_FIRMWARE",
    "-DLOCAL_MEM_EN=0",
]

# Common linker flags from build.cpp JitBuildState::link and JitBuildEnv::init
_FIRMWARE_LINKOPTS = [
    "-Wl,-z,max-page-size=16",
    "-Wl,-z,common-page-size=16",
    "-nostartfiles",
    "-Wl,--emit-relocs",
]

def firmware_binary(
        name,
        srcs,
        arch,
        proc_define,
        linker_script,
        extra_deps = [],
        extra_copts = [],
        extra_linkopts = [],
        use_tmu_crt0 = True,
        **kwargs):
    """Create a firmware cc_binary target for a specific processor.

    Args:
        name: Target name (e.g., "brisc").
        srcs: Source files to compile (e.g., ["brisc.cc"]).
        arch: Architecture ("wormhole" or "blackhole").
        proc_define: Processor define (e.g., "COMPILE_FOR_BRISC").
        linker_script: Label for the preprocessed linker script.
        extra_deps: Additional cc_library dependencies.
        extra_copts: Additional compiler flags.
        extra_linkopts: Additional linker flags.
        use_tmu_crt0: Whether to link tmu-crt0.o (False for active ERISC
            which provides its own CRT startup).
        **kwargs: Passed through to cc_binary.
    """
    includes = _COMMON_INCLUDES + _ARCH_INCLUDES.get(arch, [])
    copts = _FIRMWARE_COPTS + includes + [
        "-D" + proc_define,
        _ARCH_DEFINES[arch],
    ] + extra_copts

    deps = ["//tt_metal/hw/toolchain:substitutes"]
    if use_tmu_crt0:
        deps.append("//tt_metal/hw/toolchain:tmu_crt0")
    deps = deps + extra_deps

    native.cc_binary(
        name = name,
        srcs = srcs,
        copts = copts,
        additional_linker_inputs = [linker_script],
        linkopts = _FIRMWARE_LINKOPTS + [
            "-T$(location %s)" % linker_script,
        ] + extra_linkopts,
        deps = deps,
        **kwargs
    )

def tensix_firmware(arch):
    """Generate firmware targets for all Tensix processors on a given architecture.

    Creates cc_binary targets for BRISC, NCRISC, and TRISC (0-2).

    Args:
        arch: "wormhole" or "blackhole".
    """

    # BRISC — data mover processor 0
    firmware_binary(
        name = "brisc_" + arch,
        srcs = ["brisc.cc"],
        arch = arch,
        proc_define = "COMPILE_FOR_BRISC",
        linker_script = "//tt_metal/hw/toolchain:ld_%s_brisc_firmware" % arch,
        extra_deps = [":noc_" + arch],
    )

    # NCRISC — data mover processor 1
    ncrisc_deps = [":tdma_xmov_" + arch]
    if arch == "wormhole":
        ncrisc_deps.append("//tt_metal/hw/toolchain:wh_iram_trampoline")

    firmware_binary(
        name = "ncrisc_" + arch,
        srcs = ["ncrisc.cc"],
        arch = arch,
        proc_define = "COMPILE_FOR_NCRISC",
        linker_script = "//tt_metal/hw/toolchain:ld_%s_ncrisc_firmware" % arch,
        extra_deps = ncrisc_deps,
    )

    # TRISC 0-2 — compute processors
    for i in range(3):
        firmware_binary(
            name = "trisc%d_%s" % (i, arch),
            srcs = ["trisc.cc"],
            arch = arch,
            proc_define = "COMPILE_FOR_TRISC=%d" % i,
            linker_script = "//tt_metal/hw/toolchain:ld_%s_trisc%d_firmware" % (arch, i),
            extra_copts = [
                "-Itt_metal/hw/ckernels/%s/metal/llk_api" % (
                    "wormhole_b0" if arch == "wormhole" else arch
                ),
                "-Itt_metal/hw/ckernels/%s/metal/llk_api/llk_sfpu" % (
                    "wormhole_b0" if arch == "wormhole" else arch
                ),
            ],
        )

def ethernet_firmware(arch):
    """Generate firmware targets for Ethernet processors on a given architecture.

    Creates cc_binary targets for ERISC (active/idle/subordinate) variants.

    Args:
        arch: "wormhole" or "blackhole".
    """

    eth_includes = ["-Itt_metal/hw/inc/ethernet"]

    if arch == "wormhole":
        # Active ERISC — Wormhole uses erisc.cc with its own CRT (erisc-crt0.cc)
        firmware_binary(
            name = "erisc_" + arch,
            srcs = ["erisc.cc", "erisc-crt0.cc"],
            arch = arch,
            proc_define = "COMPILE_FOR_ERISC",
            linker_script = "//tt_metal/hw/toolchain:ld_wormhole_erisc_b0_app",
            use_tmu_crt0 = False,
            extra_copts = [
                "-DERISC",
                "-DRISC_B0_HW",
            ] + eth_includes,
        )
    else:
        # Active ERISC — Blackhole uses active_erisc.cc with its own CRT
        firmware_binary(
            name = "active_erisc_" + arch,
            srcs = ["active_erisc.cc", "active_erisc-crt0.cc"],
            arch = arch,
            proc_define = "COMPILE_FOR_ERISC",
            linker_script = "//tt_metal/hw/toolchain:ld_%s_aerisc_firmware" % arch,
            use_tmu_crt0 = False,
            extra_copts = [
                "-DERISC",
                "-DRISC_B0_HW",
            ] + eth_includes,
        )

    # Idle ERISC
    firmware_binary(
        name = "idle_erisc_" + arch,
        srcs = ["idle_erisc.cc"],
        arch = arch,
        proc_define = "COMPILE_FOR_ERISC",
        linker_script = "//tt_metal/hw/toolchain:ld_%s_ierisc_firmware" % arch,
        extra_deps = [":noc_" + arch],
        extra_copts = [
            "-DERISC",
            "-DRISC_B0_HW",
        ],
    )

    # Subordinate ERISC (idle variant)
    firmware_binary(
        name = "subordinate_erisc_" + arch,
        srcs = ["subordinate_erisc.cc"],
        arch = arch,
        proc_define = "COMPILE_FOR_ERISC",
        linker_script = "//tt_metal/hw/toolchain:ld_%s_subordinate_ierisc_firmware" % arch,
        extra_deps = [],
        extra_copts = [
            "-DERISC",
            "-DRISC_B0_HW",
        ],
    )

def all_firmware(arch):
    """Generate all firmware targets for the given architecture.

    Args:
        arch: "wormhole" or "blackhole".
    """
    tensix_firmware(arch)
    ethernet_firmware(arch)
