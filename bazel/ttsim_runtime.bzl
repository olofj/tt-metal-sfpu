"""Bazel rules for cross-compiling firmware objects and assembling a TTSim runtime tree.

The tt_metal JIT build system compiles device kernels at test runtime. It needs:
  - SFPI cross-compiler (from @sfpi)
  - Pre-compiled firmware support objects (.o files)
  - Preprocessed linker scripts (.ld files)
  - Source headers (from the workspace)

This file provides:
  - firmware_obj(): macro to cross-compile a single firmware source to .o
  - ttsim_runtime:  rule to assemble .o + .ld into the directory layout:
        hw/lib/{arch}/          <- firmware .o files
        hw/toolchain/{arch}/    <- preprocessed .ld files
"""

# ---------------------------------------------------------------------------
# Common compiler flags (from toolchain/sfpi/cc_toolchain_config.bzl)
# ---------------------------------------------------------------------------

_SFPI_COMMON_FLAGS = [
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

_FIRMWARE_DEFINES = [
    "-DTENSIX_FIRMWARE",
    "-DLOCAL_MEM_EN=0",
]

# ---------------------------------------------------------------------------
# firmware_obj: cross-compile a single source file to .o
# ---------------------------------------------------------------------------

def firmware_obj(name, src, obj_name, mcpu, hdrs = [], copts = [], visibility = None, **kwargs):
    """Cross-compile a single firmware source file using the SFPI compiler.

    Produces a .o file by invoking the SFPI RISC-V cross-compiler directly
    (no cc_library, no platform transition). Header files are explicitly
    listed so they are available in Bazel's sandbox.

    Args:
        name: Unique Bazel target name (e.g. "wh_tmu_crt0").
        src: Label of the source file (.S, .c, or .cpp).
        obj_name: Output filename (e.g. "tmu-crt0.o").
        mcpu: SFPI CPU target ("tt-wh" or "tt-bh").
        hdrs: Header filegroup labels needed for compilation.
        copts: Additional compiler flags beyond the common set.
        visibility: Bazel visibility.
        **kwargs: Passed to native.genrule.
    """
    all_flags = ["-mcpu=" + mcpu] + _SFPI_COMMON_FLAGS + _FIRMWARE_DEFINES + copts

    native.genrule(
        name = name,
        srcs = [src] + hdrs + ["@sfpi//:compiler_files"],
        outs = [name + "/" + obj_name],
        cmd = "$(location @sfpi//:gxx) " + " ".join(all_flags) +
              " -c $(location " + src + ") -o $@",
        tools = ["@sfpi//:gxx"],
        visibility = visibility,
        **kwargs
    )

# ---------------------------------------------------------------------------
# ttsim_runtime: assemble .o files and .ld scripts into a directory tree
# ---------------------------------------------------------------------------

def _ttsim_runtime_impl(ctx):
    tree = ctx.actions.declare_directory(ctx.attr.name + "_tree")
    arch_dir = ctx.attr.arch_dir

    # Collect .o files from firmware_obj genrule outputs.
    obj_files = []
    for target in ctx.attr.firmware_objs:
        for f in target[DefaultInfo].files.to_list():
            if f.extension == "o":
                obj_files.append(f)

    ld_files = ctx.files.linker_scripts

    lines = ["set -euo pipefail"]
    lib_dir = "{tree}/lib/{arch}".format(tree = tree.path, arch = arch_dir)
    toolchain_dir = "{tree}/toolchain/{arch}".format(tree = tree.path, arch = arch_dir)
    lines.append("mkdir -p " + lib_dir)
    lines.append("mkdir -p " + toolchain_dir)

    # Copy firmware objects into lib/{arch}/
    for obj in obj_files:
        lines.append("cp -L {src} {dst}/{name}".format(
            src = obj.path,
            dst = lib_dir,
            name = obj.basename,
        ))

    # Copy linker scripts into toolchain/{arch}/, stripping the arch prefix.
    # Bazel produces "wormhole_firmware_brisc.ld" but JIT expects "firmware_brisc.ld".
    # Erisc scripts ("erisc-b0-kernel.ld") have no prefix and are kept as-is.
    arch_prefix = arch_dir + "_"
    for ld_file in ld_files:
        name = ld_file.basename
        if name.startswith(arch_prefix):
            name = name[len(arch_prefix):]
        lines.append("cp -L {src} {dst}/{name}".format(
            src = ld_file.path,
            dst = toolchain_dir,
            name = name,
        ))

    ctx.actions.run_shell(
        command = "\n".join(lines),
        inputs = obj_files + ld_files,
        outputs = [tree],
        mnemonic = "AssembleTtsimRuntime",
        progress_message = "Assembling TTSim runtime for %s" % arch_dir,
    )

    return [DefaultInfo(files = depset([tree]))]

ttsim_runtime = rule(
    implementation = _ttsim_runtime_impl,
    attrs = {
        "firmware_objs": attr.label_list(
            doc = "firmware_obj targets producing .o files.",
        ),
        "linker_scripts": attr.label_list(
            allow_files = [".ld"],
            doc = "Preprocessed linker script targets.",
        ),
        "arch_dir": attr.string(
            mandatory = True,
            doc = "Architecture directory name ('wormhole' or 'blackhole').",
        ),
    },
    doc = "Assemble firmware objects and linker scripts into a JIT runtime directory tree.",
)
