"""Rules for consuming Bazel workspace version stamps.

The workspace status command (bazel/stamp_version.sh) produces key-value pairs
like STABLE_VERSION, STABLE_GIT_COMMIT, etc. These rules extract individual
values into files that other targets (py_wheel, pkg_deb, genrule) can consume.

Usage:
    load("//bazel:stamp_version.bzl", "stamp_version")

    stamp_version(
        name = "version",
        key = "STABLE_VERSION",
    )

    # Produces :version.txt containing e.g. "1.2.3" or "1.2.4.dev5"
    # With --stamp: rebuilds when version changes
    # With --nostamp (default): cached, does not rebuild on git changes

Example in a genrule:
    genrule(
        name = "version_header",
        srcs = [":version"],
        outs = ["version.h"],
        cmd = "echo '#define VERSION \"'$$(cat $<)'\"' > $@",
    )
"""

def _stamp_version_impl(ctx):
    output = ctx.actions.declare_file(ctx.attr.name + ".txt")
    key = ctx.attr.key

    # ctx.version_file = stable status (STABLE_* keys)
    # ctx.info_file = volatile status (BUILD_TIMESTAMP, etc.)
    # Both are always populated by the workspace status command.
    # --stamp/--nostamp controls whether changes trigger cache invalidation.
    ctx.actions.run_shell(
        outputs = [output],
        inputs = [ctx.info_file, ctx.version_file],
        command = """
            value=$(grep "^{key} " "{version}" "{info}" 2>/dev/null | head -1 | cut -d" " -f2-)
            if [ -z "$value" ]; then
                printf '%s' "{fallback}" > "{output}"
            else
                printf '%s' "$value" > "{output}"
            fi
        """.format(
            key = key,
            version = ctx.version_file.path,
            info = ctx.info_file.path,
            output = output.path,
            fallback = ctx.attr.fallback,
        ),
    )

    return [DefaultInfo(files = depset([output]))]

stamp_version = rule(
    implementation = _stamp_version_impl,
    attrs = {
        "key": attr.string(
            mandatory = True,
            doc = "Workspace status key to extract (e.g., STABLE_VERSION, STABLE_GIT_COMMIT).",
        ),
        "fallback": attr.string(
            default = "0.0.0.dev0",
            doc = "Value used when the key is not found in workspace status.",
        ),
    },
    doc = "Extracts a single key from Bazel workspace status into a text file.",
)
