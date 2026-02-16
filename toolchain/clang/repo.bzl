"""Repository rule to download a pre-built LLVM/Clang 20 toolchain.

Downloads the official LLVM release from GitHub so the Bazel build does
not require a system-installed clang-20 package.  Follows the same
pattern as toolchain/sfpi/repo.bzl.

The tarball includes clang, clang++, lld (used in place of mold),
llvm-ar, llvm-nm, llvm-objcopy, llvm-objdump, llvm-strip, libc++
headers and libraries, and compiler-rt builtins.
"""

LLVM_VERSION = "20.1.8"
_LLVM_REPO = "https://github.com/llvm/llvm-project"

# SHA256 hashes for official LLVM release tarballs.
# Keys are "{arch}" matching the GitHub release naming convention.
_LLVM_HASHES = {
    "x86_64": "1ead36b3dfcb774b57be530df42bec70ab2d239fbce9889447c7a29a4ddc1ae6",
    # aarch64 hash should be added after verification.
    # "aarch64": "",
}

# Maps uname -m output to LLVM release filename arch component.
_ARCH_MAP = {
    "x86_64": "X64",
    "aarch64": "ARM64",
}

def _detect_arch(ctx):
    """Detect host CPU architecture."""
    res = ctx.execute(["uname", "-m"])
    if res.return_code != 0:
        fail("Failed to detect architecture: " + res.stderr)
    return res.stdout.strip()

def _clang_toolchain_repo_impl(ctx):
    arch = _detect_arch(ctx)

    if arch not in _LLVM_HASHES:
        fail(
            "No pre-built LLVM toolchain available for {arch}. ".format(arch = arch) +
            "Available architectures: " + ", ".join(_LLVM_HASHES.keys()),
        )

    release_arch = _ARCH_MAP.get(arch, arch)
    version = ctx.attr.version
    filename = "LLVM-{version}-Linux-{arch}.tar.xz".format(
        version = version,
        arch = release_arch,
    )
    url = "{repo}/releases/download/llvmorg-{version}/{filename}".format(
        repo = _LLVM_REPO,
        version = version,
        filename = filename,
    )

    ctx.download_and_extract(
        url = url,
        sha256 = _LLVM_HASHES[arch],
        type = "tar.xz",
        stripPrefix = "LLVM-{version}-Linux-{arch}".format(
            version = version,
            arch = release_arch,
        ),
    )

    # Copy the toolchain config rule into the repository so tool_path
    # references resolve relative to this package (where the binaries live).
    ctx.symlink(ctx.attr._cc_toolchain_config, "cc_toolchain_config.bzl")

    # Generate BUILD.bazel with toolchain targets for each stdlib variant.
    toolchain_defs = []
    for name, stdlib in _STDLIB_VARIANTS:
        toolchain_defs.append(_TOOLCHAIN_TEMPLATE.format(
            name = name,
            stdlib = stdlib,
        ))

    ctx.file("BUILD.bazel", content = _BUILD_HEADER + "\n".join(toolchain_defs))

# Two variants: libc++ (bundled) and libstdc++ (system).
_STDLIB_VARIANTS = [
    ("libcpp", "libc++"),
    ("libstdcpp", "libstdc++"),
]

_BUILD_HEADER = """\
load(":cc_toolchain_config.bzl", "clang_cc_toolchain_config")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_files",
    srcs = glob(["**"]),
)

filegroup(
    name = "compiler_files",
    srcs = glob([
        "bin/clang",
        "bin/clang++",
        "bin/clang-20",
        "bin/clang-cpp",
        "lib/clang/20/**",
        "include/c++/**",
        "include/x86_64-unknown-linux-gnu/**",
    ]),
)

filegroup(
    name = "linker_files",
    srcs = glob([
        "bin/clang",
        "bin/clang++",
        "bin/clang-20",
        "bin/ld.lld",
        "bin/lld",
        "lib/clang/20/**",
        "lib/x86_64-unknown-linux-gnu/**",
    ]),
)

filegroup(
    name = "ar_files",
    srcs = ["bin/llvm-ar"],
)

filegroup(
    name = "objcopy_files",
    srcs = ["bin/llvm-objcopy"],
)

filegroup(
    name = "strip_files",
    srcs = ["bin/llvm-strip"],
)

filegroup(
    name = "dwp_files",
    srcs = ["bin/llvm-dwp"],
)

filegroup(
    name = "empty",
    srcs = [],
)

"""

_TOOLCHAIN_TEMPLATE = """\
# ===================================================================
# Clang 20 + {stdlib}
# ===================================================================

clang_cc_toolchain_config(
    name = "clang20_{name}_config",
    stdlib = "{stdlib}",
)

cc_toolchain(
    name = "clang20_{name}_cc_toolchain",
    all_files = ":all_files",
    ar_files = ":ar_files",
    compiler_files = ":compiler_files",
    dwp_files = ":dwp_files",
    linker_files = ":linker_files",
    objcopy_files = ":objcopy_files",
    strip_files = ":strip_files",
    toolchain_config = ":clang20_{name}_config",
)

"""

clang_toolchain_repo = repository_rule(
    implementation = _clang_toolchain_repo_impl,
    attrs = {
        "version": attr.string(default = LLVM_VERSION),
        "_cc_toolchain_config": attr.label(
            default = "//toolchain/clang:cc_toolchain_config.bzl",
            allow_single_file = True,
        ),
    },
    environ = ["PATH"],
)
