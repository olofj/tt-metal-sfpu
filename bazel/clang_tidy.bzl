"""Bazel aspect for running clang-tidy on C++ targets.

Mirrors the CMake clang-tidy integration (CMakePresets.json clang-tidy preset)
using the hermetic Clang 20 toolchain's bundled clang-tidy binary.

Usage:
  # Lint all C++ targets:
  bazel build --config=clang-tidy //...

  # Lint a specific target:
  bazel build --aspects=//bazel:clang_tidy.bzl%clang_tidy_aspect \\
      --output_groups=clang_tidy //<target>

The aspect reads .clang-tidy configuration files from the source tree
automatically (clang-tidy's native parent-directory walk). External
dependencies are skipped.
"""

ClangTidyInfo = provider(
    doc = "Collects clang-tidy report files from a target and its transitive deps.",
    fields = {"reports": "depset of clang-tidy report Files"},
)

_SCRIPT = """\
#!/usr/bin/env bash
set -euo pipefail
CLANG_TIDY="$1"; shift
REPORT="$1"; shift

if "$CLANG_TIDY" "$@" > "$REPORT" 2>&1; then
    echo "PASS" >> "$REPORT"
else
    rc=$?
    cat "$REPORT" >&2
    exit $rc
fi
"""

def _clang_tidy_aspect_impl(target, ctx):
    # Skip external targets — third-party code has its own .clang-tidy
    # disable config and should not be linted.
    if target.label.workspace_name:
        return [ClangTidyInfo(reports = depset())]

    # Only process targets that provide CcInfo.
    if CcInfo not in target:
        return [ClangTidyInfo(reports = depset())]

    # Collect reports from deps for transitive propagation.
    dep_reports = []
    if hasattr(ctx.rule.attr, "deps"):
        for dep in ctx.rule.attr.deps:
            if ClangTidyInfo in dep:
                dep_reports.append(dep[ClangTidyInfo].reports)

    # Gather C/C++ source files.
    srcs = []
    if hasattr(ctx.rule.attr, "srcs"):
        for src in ctx.rule.attr.srcs:
            for f in src.files.to_list():
                if f.extension in ("c", "cc", "cpp", "cxx", "c++", "C"):
                    srcs.append(f)

    if not srcs:
        return [
            ClangTidyInfo(reports = depset(transitive = dep_reports)),
            OutputGroupInfo(clang_tidy = depset(transitive = dep_reports)),
        ]

    # Extract compilation context.
    comp_ctx = target[CcInfo].compilation_context

    # Build compiler flags from CcInfo — these mirror what the actual
    # compile action sees, ensuring clang-tidy resolves headers correctly.
    compiler_flags = [
        "-std=c++20",
        "-march=x86-64-v3",
        "-fPIC",
    ]

    for d in comp_ctx.includes.to_list():
        compiler_flags.extend(["-isystem", d])
    for d in comp_ctx.system_includes.to_list():
        compiler_flags.extend(["-isystem", d])
    for d in comp_ctx.quote_includes.to_list():
        compiler_flags.extend(["-iquote", d])
    for d in comp_ctx.framework_includes.to_list():
        compiler_flags.extend(["-F", d])
    for d in comp_ctx.defines.to_list():
        compiler_flags.append("-D" + d)
    for d in comp_ctx.local_defines.to_list():
        compiler_flags.append("-D" + d)

    clang_tidy_exe = ctx.executable._clang_tidy
    headers = comp_ctx.headers

    reports = []
    for src in srcs:
        # Use full short_path with '/' replaced to avoid basename collisions.
        safe_name = src.short_path.replace("/", "_")
        report = ctx.actions.declare_file(
            "_clang_tidy/{}.clang-tidy".format(safe_name),
        )
        reports.append(report)

        # Arguments: <clang-tidy-exe> <report> <tidy-flags...> <source> -- <compiler-flags...>
        args = ctx.actions.args()
        args.add(clang_tidy_exe)
        args.add(report)
        args.add("--warnings-as-errors=*")
        args.add("--header-filter=.*")
        args.add(src)
        args.add("--")
        args.add("-x")
        args.add("c++")
        args.add_all(compiler_flags)

        ctx.actions.run_shell(
            outputs = [report],
            inputs = depset([src], transitive = [headers]),
            tools = [clang_tidy_exe],
            arguments = [args],
            command = _SCRIPT,
            mnemonic = "ClangTidy",
            progress_message = "Linting %s" % src.short_path,
        )

    all_reports = depset(reports, transitive = dep_reports)
    return [
        ClangTidyInfo(reports = all_reports),
        OutputGroupInfo(clang_tidy = all_reports),
    ]

clang_tidy_aspect = aspect(
    implementation = _clang_tidy_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_clang_tidy": attr.label(
            default = "@llvm_clang//:clang_tidy",
            executable = True,
            cfg = "exec",
        ),
    },
    fragments = ["cpp"],
)
