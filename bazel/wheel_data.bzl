"""Rules for staging data files into py_wheel-compatible paths.

The py_wheel rule from rules_python places files using their short_path,
with optional strip_path_prefixes. For data files that need a different
wheel-internal path than their workspace path, these rules create symlinks
at paths that, after stripping, produce the correct wheel layout.

Example: tt_metal/hw/foo.h needs to land at ttnn/tt_metal/hw/foo.h in the
wheel. A symlink is created at _whl/ttnn/tt_metal/hw/foo.h. With
strip_path_prefixes=["_whl/"], the file correctly lands at
ttnn/tt_metal/hw/foo.h.
"""

def _wheel_remap_impl(ctx):
    """Create symlinks that remap source files to wheel-compatible paths."""
    prefix = ctx.attr.prefix
    strip = ctx.attr.strip_prefix
    outputs = []

    for src in ctx.attr.srcs:
        for f in src.files.to_list():
            if f.is_directory:
                continue

            # Compute the relative path (strip source prefix if specified)
            rel_path = f.short_path
            if strip and rel_path.startswith(strip):
                rel_path = rel_path[len(strip):]

            # Build the output path under _whl/ staging area
            if prefix:
                dest_path = "_whl/%s/%s" % (prefix, rel_path)
            else:
                dest_path = "_whl/%s" % rel_path

            out = ctx.actions.declare_file(dest_path)
            ctx.actions.symlink(output = out, target_file = f)
            outputs.append(out)

    return [DefaultInfo(files = depset(outputs))]

wheel_remap = rule(
    implementation = _wheel_remap_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Source files or filegroups to include in the wheel.",
        ),
        "prefix": attr.string(
            default = "",
            doc = "Prefix path inside the wheel (e.g., 'ttnn' to put files under ttnn/).",
        ),
        "strip_prefix": attr.string(
            default = "",
            doc = "Prefix to strip from source file paths before applying the new prefix.",
        ),
    },
    doc = """Remap files to wheel-compatible paths via symlinks.

Creates symlinks under _whl/<prefix>/<relative_path> for each input file.
Use strip_path_prefixes=["_whl/"] on the py_wheel target to remove the
staging prefix.

Example:
    wheel_remap(
        name = "wheel_tt_metal_data",
        srcs = ["//tt_metal:jit_data"],
        prefix = "ttnn/tt_metal",
        strip_prefix = "tt_metal/",
    )
    # tt_metal/hw/foo.h → _whl/ttnn/tt_metal/hw/foo.h → (strip _whl/) → ttnn/tt_metal/hw/foo.h
""",
)
