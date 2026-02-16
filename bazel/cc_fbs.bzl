"""Bazel rules for compiling FlatBuffers schemas to C++.

These rules use flatc v24.3.25 from @flatbuffers to generate *_generated.h
headers, matching the CMake build's GENERATE_FBS_HEADER() function in
cmake/flatbuffers.cmake.

Flags match CMake: --keep-prefix --cpp --scoped-enums
"""

load("@rules_cc//cc:cc_library.bzl", "cc_library")

FbsInfo = provider(
    doc = "Information about FlatBuffer schema files and their include root.",
    fields = {
        "srcs": "depset of .fbs source files",
        "include_root": "String path prefix passed as -I to flatc",
    },
)

def _fbs_library_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        FbsInfo(
            srcs = depset(ctx.files.srcs),
            include_root = ctx.attr.include_root,
        ),
    ]

fbs_library = rule(
    implementation = _fbs_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".fbs"],
            mandatory = True,
        ),
        "include_root": attr.string(
            doc = "Workspace-relative path to use as -I for flatc. " +
                  "E.g., 'tt_metal/api' so flatc can resolve " +
                  "'include \"tt-metalium/serialized_descriptors/mesh_coordinate.fbs\"'.",
            default = "",
        ),
    },
)

def _src_rel_path(ctx, src):
    """Return the source file's path relative to the package directory."""
    pkg = ctx.label.package
    if pkg and src.path.startswith(pkg + "/"):
        return src.path[len(pkg) + 1:]
    return src.basename

def _fbs_gen_impl(ctx):
    """Generate C++ headers from .fbs files using flatc."""
    outputs = []

    # Collect all include roots and dependency .fbs files.
    dep_files = []
    include_roots = []
    for dep in ctx.attr.fbs_deps:
        if FbsInfo in dep:
            info = dep[FbsInfo]
            dep_files.append(info.srcs)
            if info.include_root:
                include_roots.append(info.include_root)
        else:
            dep_files.append(dep.files)

    all_dep_files = depset(transitive = dep_files)

    for src in ctx.files.srcs:
        # Preserve subdirectory structure in output path.
        # E.g., "tt-metalium/serialized_descriptors/mesh_coordinate.fbs"
        # becomes "tt-metalium/serialized_descriptors/mesh_coordinate_generated.h"
        rel = _src_rel_path(ctx, src)
        stem = rel[:-len(".fbs")]
        h = ctx.actions.declare_file(stem + "_generated.h")
        outputs.append(h)

        args = ctx.actions.args()
        args.add("--cpp")
        args.add("--scoped-enums")
        args.add("--keep-prefix")
        args.add("-o", h.dirname)

        # Add the source file's directory so co-located includes resolve.
        args.add("-I", src.dirname)

        # Add include roots from dependencies.
        for root in include_roots:
            args.add("-I", root)

        args.add(src)

        ctx.actions.run(
            executable = ctx.executable._flatc,
            arguments = [args],
            inputs = depset(
                direct = [src],
                transitive = [depset(ctx.files.srcs), all_dep_files],
            ),
            outputs = [h],
            mnemonic = "FlatcCompile",
            progress_message = "Generating C++ header from %{input}",
        )

    return [DefaultInfo(files = depset(outputs))]

_fbs_gen = rule(
    implementation = _fbs_gen_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".fbs"],
            mandatory = True,
        ),
        "fbs_deps": attr.label_list(
            doc = "Schema dependencies providing FbsInfo (fbs_library targets).",
        ),
        "_flatc": attr.label(
            default = "@flatbuffers//:flatc",
            executable = True,
            cfg = "exec",
        ),
    },
)

def cc_fbs_library(name, srcs, fbs_deps = [], deps = [], visibility = None):
    """Compile .fbs files to a C++ header-only library.

    Generates *_generated.h from each .fbs source, then wraps them in
    a cc_library that links against @flatbuffers//:flatbuffers (the runtime).

    The cc_library always sets includes = ["."] so that generated headers
    can be included with bare filenames (matching CMake's include path setup).

    Args:
        name: Target name for the resulting cc_library.
        srcs: List of .fbs source files to compile.
        fbs_deps: fbs_library targets whose schemas are needed for include
            resolution. Their include_root is passed as -I to flatc.
        deps: Additional cc_library dependencies (e.g., other cc_fbs_library targets).
        visibility: Bazel visibility specification.
    """
    gen_name = name + "_gen"

    _fbs_gen(
        name = gen_name,
        srcs = srcs,
        fbs_deps = fbs_deps,
    )

    cc_library(
        name = name,
        hdrs = [":" + gen_name],
        includes = ["."],
        deps = ["@flatbuffers//:flatbuffers"] + deps,
        visibility = visibility,
    )
