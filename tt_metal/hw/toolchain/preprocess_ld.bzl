"""Rule for preprocessing linker script templates through the C preprocessor.

Linker scripts (.ld) use C preprocessor directives (#ifdef, #include, etc.)
to generate per-processor, per-architecture variants from a single template.

The CMake build does this via:
    ${CMAKE_CXX_COMPILER} -E -P -x c -DCOMPILE_FOR_${PROC} -DARCH_${ARCH} ...

This Bazel rule replicates that using the host CC toolchain's preprocessor.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")

def _preprocess_ld_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    out = ctx.actions.declare_file(ctx.attr.out_name)

    # Build include-path flags. We add the dirname of each include file
    # so that #include "dev_mem_map.h" resolves correctly.
    include_dirs = {f.dirname: True for f in ctx.files.includes}

    args = [cc_toolchain.compiler_executable, "-E", "-P", "-x", "c"]
    for define in ctx.attr.defines:
        args.append("-D" + define)
    for d in include_dirs:
        args.extend(["-I", d])
    args.extend(["-o", out.path, ctx.file.src.path])

    ctx.actions.run_shell(
        command = " ".join(["'" + a.replace("'", "'\\''") + "'" for a in args]),
        inputs = depset(
            [ctx.file.src] + ctx.files.includes,
            transitive = [cc_toolchain.all_files],
        ),
        outputs = [out],
        mnemonic = "PreprocessLd",
        progress_message = "Preprocessing linker script %{output}",
    )

    return [DefaultInfo(files = depset([out]))]

preprocess_ld = rule(
    implementation = _preprocess_ld_impl,
    attrs = {
        "src": attr.label(
            mandatory = True,
            allow_single_file = [".ld"],
            doc = "Linker script template to preprocess.",
        ),
        "includes": attr.label_list(
            allow_files = True,
            doc = "Header files needed during preprocessing (e.g. dev_mem_map.h).",
        ),
        "defines": attr.string_list(
            doc = "Preprocessor defines (without -D prefix), e.g. ['COMPILE_FOR_BRISC', 'ARCH_WORMHOLE'].",
        ),
        "out_name": attr.string(
            mandatory = True,
            doc = "Output filename for the preprocessed linker script.",
        ),
        "_cc_toolchain": attr.label(
            default = "@rules_cc//cc:current_cc_toolchain",
        ),
    },
    toolchains = ["@rules_cc//cc:toolchain_type"],
    fragments = ["cpp"],
    doc = "Preprocess a linker script template through the C preprocessor.",
)

def preprocess_main_ld(name, arch, proc, type, includes, **kwargs):
    """Generate a preprocessed linker script from main.ld.

    Mirrors the CMake logic in tt_metal/hw/CMakeLists.txt lines 211-234.

    Args:
        name: Bazel target name.
        arch: Architecture name, uppercase (e.g. "WORMHOLE", "BLACKHOLE").
        proc: Processor define suffix (e.g. "BRISC", "TRISC=0").
        type: Type name, uppercase (e.g. "FIRMWARE", "KERNEL").
        includes: List of labels for include headers.
        **kwargs: Passed through to preprocess_ld.
    """
    # CMake strips '=' from proc name for the output filename.
    # Include arch in filename to avoid Bazel action conflicts when
    # multiple architectures produce scripts for the same processor.
    proc_file = proc.replace("=", "")
    out_name = "%s_%s_%s.ld" % (arch.lower(), type.lower(), proc_file.lower())

    preprocess_ld(
        name = name,
        src = "main.ld",
        includes = includes,
        defines = [
            "COMPILE_FOR_" + proc,
            "ARCH_" + arch,
            "TYPE_" + type,
        ],
        out_name = out_name,
        **kwargs
    )

def preprocess_erisc_ld(name, script_type, includes, enable_iram = False, **kwargs):
    """Generate a preprocessed erisc-b0 linker script (wormhole only).

    Mirrors CMake logic in tt_metal/hw/CMakeLists.txt lines 178-208.

    Args:
        name: Bazel target name.
        script_type: "kernel" or "app".
        includes: List of labels for include headers.
        enable_iram: Whether to define ENABLE_IRAM.
        **kwargs: Passed through to preprocess_ld.
    """
    defines = []
    if enable_iram:
        defines.append("ENABLE_IRAM")
        out_name = "erisc-b0-%s_iram.ld" % script_type
    else:
        out_name = "erisc-b0-%s.ld" % script_type

    preprocess_ld(
        name = name,
        src = "erisc-b0-%s.ld" % script_type,
        includes = includes,
        defines = defines,
        out_name = out_name,
        **kwargs
    )

def preprocess_tng_ld(name, arch, proc, type, ix, includes, **kwargs):
    """Generate a preprocessed TLS-style linker script from script_tng.ld.

    Mirrors CMake logic in tt_metal/hw/CMakeLists.txt lines 242-294.

    Args:
        name: Bazel target name.
        arch: Architecture name, uppercase (e.g. "QUASAR").
        proc: Processor name, uppercase (e.g. "TRISC", "DM").
        type: "FIRMWARE" or "KERNEL".
        ix: Index (0 for base, 1 for legacy kernel "_lgc" variant).
        includes: List of labels for include headers.
        **kwargs: Passed through to preprocess_ld.
    """
    lgc = "_lgc" if ix else ""
    out_name = "%s_%s%s.ld" % (type.lower(), proc.lower(), lgc)

    preprocess_ld(
        name = name,
        src = "script_tng.ld",
        includes = includes,
        defines = [
            "COMPILE_FOR_" + proc,
            "ARCH_" + arch,
            "TYPE_%s=%d" % (type, ix),
        ],
        out_name = out_name,
        **kwargs
    )
