"""Rule for weakening ELF symbols in firmware binaries.

Firmware ELFs must be "weakened" before they can be used as libraries for
JIT-linking user kernels.  This replaces the runtime JitBuildState::weaken()
call in tt_metal/jit_build/build.cpp (lines 583-597) with a build-time step.

The weakener preserves __fw_export_* and __global_pointer$ symbols at full
strength while localizing other function symbols and weakening data symbols.
This prevents duplicate-symbol conflicts when user kernels link against
firmware while still allowing kernels to access exported firmware functions.
"""

def _weaken_firmware_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.out_name)

    args = ctx.actions.args()
    if ctx.attr.objectify:
        args.add("--objectify")
    args.add(ctx.file.firmware.path)
    args.add(out.path)

    ctx.actions.run(
        executable = ctx.executable._weakener,
        arguments = [args],
        inputs = [ctx.file.firmware],
        outputs = [out],
        mnemonic = "WeakenFirmware",
        progress_message = "Weakening firmware symbols %{output}",
    )

    return [DefaultInfo(files = depset([out]))]

weaken_firmware = rule(
    implementation = _weaken_firmware_impl,
    attrs = {
        "firmware": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Input firmware ELF binary to weaken.",
        ),
        "out_name": attr.string(
            mandatory = True,
            doc = "Output filename for the weakened ELF.",
        ),
        "objectify": attr.bool(
            default = False,
            doc = "Also convert the executable to a relocatable object (for tt-2xx architectures).",
        ),
        "_weakener": attr.label(
            default = "//tt_metal/hw/toolchain:weaken_firmware_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Weaken ELF symbols in a firmware binary, preserving __fw_export_* at full strength.",
)
