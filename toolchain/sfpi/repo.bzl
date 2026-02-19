"""Repository rule to download the pre-built SFPI RISC-V cross-compiler.

The SFPI (Scalar Friendly Programming Interface) toolchain is a custom
RISC-V compiler with Tenstorrent-specific extensions (-mcpu=tt-wh,
-mcpu=tt-bh, etc.) used to compile device firmware and kernels.

Source of truth for version/hashes: tt_metal/sfpi-version
Source of truth for URLs/platforms: tt_metal/sfpi-info.sh
"""

# SFPI version — update when tt_metal/sfpi-version changes.
SFPI_VERSION = "7.25.0"
SFPI_REPO = "https://github.com/tenstorrent/sfpi"

# SHA256 hashes from tt_metal/sfpi-version (txz packages only).
# Keys are "{arch}_{distro}" matching sfpi-info.sh naming convention.
_SFPI_HASHES = {
    "x86_64_debian": "6a8883c448df537d9661e239e67721b1ba2a4d0e8ea7a573070d2f6c6d015093",
    "x86_64_fedora": "8dbda7d0505865123218b3fa3d7c44946c5f843b144dc9b4b160d1248ce68836",
    "aarch64_debian": "13d44145544d0c81209f8ab069b4de931fbd38ea2c3b4e4f02be2dc8af6eb8c6",
}

# Architecture variants: (config_name, mcpu_flag)
_ARCH_VARIANTS = [
    ("wormhole", "tt-wh"),
    ("blackhole", "tt-bh"),
    ("quasar32", "tt-qsr32"),
    ("quasar64", "tt-qsr64"),
]

def _detect_platform(ctx):
    """Detect host architecture and distro family, matching sfpi-info.sh logic."""
    res = ctx.execute(["uname", "-m"])
    if res.return_code != 0:
        fail("Failed to detect architecture: " + res.stderr)
    arch = res.stdout.strip()

    # Detect distro family: check /etc/os-release for ID and ID_LIKE
    distro = "debian"  # default fallback
    res = ctx.execute(["bash", "-c", """
        if [ -r /etc/os-release ]; then
            . /etc/os-release
            for like in $ID $ID_LIKE; do
                case $like in
                    debian) echo debian; exit 0;;
                    fedora) echo fedora; exit 0;;
                esac
            done
        fi
        echo debian
    """])
    if res.return_code == 0:
        distro = res.stdout.strip()

    return arch, distro

def _sfpi_toolchain_repo_impl(ctx):
    arch, distro = _detect_platform(ctx)
    platform_key = arch + "_" + distro

    if platform_key not in _SFPI_HASHES:
        fail(
            "No pre-built SFPI toolchain available for {arch} {distro}. " +
            "Available platforms: {platforms}".format(
                arch = arch,
                distro = distro,
                platforms = ", ".join(_SFPI_HASHES.keys()),
            ),
        )

    version = ctx.attr.version
    filename = "sfpi_{version}_{arch}_{distro}.txz".format(
        version = version,
        arch = arch,
        distro = distro,
    )
    url = "{repo}/releases/download/{version}/{filename}".format(
        repo = SFPI_REPO,
        version = version,
        filename = filename,
    )

    ctx.download_and_extract(
        url = url,
        sha256 = _SFPI_HASHES[platform_key],
        type = "tar.xz",
        stripPrefix = "sfpi",
    )

    # Copy the toolchain config rule into the repository so tool_path
    # references resolve relative to this package (where the binaries live).
    ctx.symlink(ctx.attr._cc_toolchain_config, "cc_toolchain_config.bzl")

    # Generate toolchain targets for each architecture variant.
    # Tool paths are relative to this package, so "compiler/bin/..." works.
    toolchain_defs = []
    for name, mcpu in _ARCH_VARIANTS:
        toolchain_defs.append(_TOOLCHAIN_TEMPLATE.format(
            name = name,
            mcpu = mcpu,
        ))

    ctx.file("BUILD.bazel", content = _BUILD_HEADER + "\n".join(toolchain_defs))

_BUILD_HEADER = """\
load(":cc_toolchain_config.bzl", "sfpi_cc_toolchain_config")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_files",
    srcs = glob(["**"]),
)

filegroup(
    name = "compiler_files",
    srcs = glob([
        "compiler/bin/**",
        "compiler/lib/**",
        "compiler/libexec/**",
        "compiler/riscv-tt-elf/**",
    ]),
)

filegroup(
    name = "linker_files",
    srcs = glob([
        "compiler/bin/**",
        "compiler/lib/**",
        "compiler/libexec/**",
        "compiler/riscv-tt-elf/**",
    ]),
)

filegroup(
    name = "gxx",
    srcs = ["compiler/bin/riscv-tt-elf-g++"],
)

filegroup(
    name = "empty",
    srcs = [],
)

"""

_TOOLCHAIN_TEMPLATE = """\
# ===================================================================
# {name} toolchain (-mcpu={mcpu})
# ===================================================================

sfpi_cc_toolchain_config(
    name = "sfpi_{name}_config",
    mcpu = "{mcpu}",
)

cc_toolchain(
    name = "sfpi_{name}_cc_toolchain",
    all_files = ":all_files",
    ar_files = ":compiler_files",
    compiler_files = ":compiler_files",
    dwp_files = ":empty",
    linker_files = ":linker_files",
    objcopy_files = ":all_files",
    strip_files = ":all_files",
    toolchain_config = ":sfpi_{name}_config",
)

"""

sfpi_toolchain_repo = repository_rule(
    implementation = _sfpi_toolchain_repo_impl,
    attrs = {
        "version": attr.string(default = SFPI_VERSION),
        "_cc_toolchain_config": attr.label(
            default = "//toolchain/sfpi:cc_toolchain_config.bzl",
            allow_single_file = True,
        ),
    },
    environ = ["PATH"],
)
