"""Bazel rules for compiling Protocol Buffer schemas to C++.

These rules use protoc v21.12 from @protobuf to generate .pb.h and .pb.cc
files, matching the CMake build's GENERATE_PROTO_FILES() function in
cmake/protobuf.cmake.
"""

load("@rules_cc//cc:cc_library.bzl", "cc_library")

def _proto_gen_impl(ctx):
    """Generate C++ sources from .proto files using protoc."""
    all_srcs = ctx.files.srcs
    outputs = []
    for src in all_srcs:
        stem = src.basename[:-len(".proto")]
        cc = ctx.actions.declare_file(stem + ".pb.cc")
        h = ctx.actions.declare_file(stem + ".pb.h")
        outputs.extend([cc, h])

        # Collect all unique proto directories so cross-file imports resolve.
        proto_dirs = {s.dirname: True for s in all_srcs}
        args = ctx.actions.args()
        args.add("--experimental_allow_proto3_optional")
        args.add("--cpp_out", cc.dirname)
        for d in proto_dirs:
            args.add("-I", d)
        args.add(src)

        ctx.actions.run(
            executable = ctx.executable._protoc,
            arguments = [args],
            inputs = all_srcs,
            outputs = [cc, h],
            mnemonic = "ProtoCompile",
            progress_message = "Generating C++ from %{input}",
        )

    return [DefaultInfo(files = depset(outputs))]

_proto_gen = rule(
    implementation = _proto_gen_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".proto"],
            mandatory = True,
        ),
        "_protoc": attr.label(
            default = "@protobuf//:protoc",
            executable = True,
            cfg = "exec",
        ),
    },
)

def cc_proto_library(name, srcs, visibility = None):
    """Compile .proto files to a C++ library.

    Generates .pb.h and .pb.cc from each .proto source, then wraps them in
    a cc_library that links against @protobuf//:protobuf.

    Args:
        name: Target name for the resulting cc_library.
        srcs: List of .proto source files.
        visibility: Bazel visibility specification.
    """
    gen_name = name + "_gen"

    _proto_gen(
        name = gen_name,
        srcs = srcs,
    )

    cc_library(
        name = name,
        srcs = [":" + gen_name],
        deps = ["@protobuf//:protobuf"],
        visibility = visibility,
    )
