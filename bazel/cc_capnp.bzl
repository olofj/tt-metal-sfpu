"""Bazel rules for compiling Cap'n Proto schemas to C++.

These rules use the capnproto compiler tools from @capnproto to generate
.capnp.h and .capnp.c++ files, matching the CMake build's
capnp_generate_cpp() function.

This custom rule handles output directory layout and system-schema import
resolution needed by tt-metal's .capnp files. It references @capnproto
targets using the repo name from our MODULE.bazel/extensions.bzl.
"""

load("@rules_cc//cc:cc_library.bzl", "cc_library")

def _capnp_gen_impl(ctx):
    """Generate C++ source and header from .capnp files."""
    outputs = []

    # Collect system schema files for import resolution.
    system_capnp = ctx.files._capnp_system
    system_include = system_capnp[0].dirname.removesuffix("/capnp") if system_capnp else ""

    for src in ctx.files.srcs:
        # Preserve directory structure relative to package.
        # e.g., "debug/inspector/rpc.capnp" → "debug/inspector/rpc.capnp.h"
        rel_path = src.short_path
        pkg_prefix = ctx.label.package + "/"
        if rel_path.startswith(pkg_prefix):
            rel_path = rel_path[len(pkg_prefix):]

        h = ctx.actions.declare_file(rel_path + ".h")
        cc = ctx.actions.declare_file(rel_path + ".c++")
        outputs.extend([h, cc])

        args = ctx.actions.args()
        args.add("compile")
        args.add("--verbose")
        args.add("-o%s:%s" % (ctx.executable._capnpc_cxx.path, h.dirname))

        # Add source directory for local imports.
        args.add("-I", src.dirname)

        # Add system include for standard capnp schemas (c++.capnp, etc.).
        if system_include:
            args.add("-I", system_include)

        # Add the source prefix so output filenames are just basename.capnp.{h,c++}.
        args.add("--src-prefix", src.dirname)

        args.add(src)

        ctx.actions.run(
            executable = ctx.executable._capnpc,
            arguments = [args],
            inputs = [src] + system_capnp + ctx.files._capnpc_cxx + ctx.files._capnpc_capnp,
            outputs = [h, cc],
            mnemonic = "CapnpCompile",
            progress_message = "Generating C++ from %{input}",
        )

    return [DefaultInfo(files = depset(outputs))]

_capnp_gen = rule(
    implementation = _capnp_gen_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".capnp"],
            mandatory = True,
        ),
        "_capnpc": attr.label(
            default = "@capnproto//src/capnp:capnp_tool",
            executable = True,
            cfg = "exec",
        ),
        "_capnpc_cxx": attr.label(
            default = "@capnproto//src/capnp:capnpc-c++",
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "_capnpc_capnp": attr.label(
            default = "@capnproto//src/capnp:capnpc-capnp",
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "_capnp_system": attr.label(
            default = "@capnproto//src/capnp:capnp_system_library",
        ),
    },
)

def cc_capnp_library(name, srcs, deps = [], visibility = None):
    """Compile .capnp files to a C++ library.

    Generates .capnp.h and .capnp.c++ from each .capnp source, then wraps
    them in a cc_library that links against the capnproto runtime.

    Args:
        name: Target name for the resulting cc_library.
        srcs: List of .capnp source files.
        deps: Additional cc_library dependencies.
        visibility: Bazel visibility specification.
    """
    gen_name = name + "_gen"

    _capnp_gen(
        name = gen_name,
        srcs = srcs,
    )

    cc_library(
        name = name,
        srcs = [":" + gen_name],
        hdrs = [":" + gen_name],
        deps = [
            "@capnproto//src/capnp",
            "@capnproto//src/capnp:capnp-rpc",
        ] + deps,
        visibility = visibility,
    )
