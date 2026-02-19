"""Bazel macro for running tests under the TTSim hardware simulator.

TTSim is a software simulator for Tenstorrent ASICs. Tests wrapped with
ttsim_test run on any machine (no hardware required) — Bazel downloads
the simulator library automatically, cross-compiles firmware objects
with the SFPI toolchain, and preprocesses linker scripts.

Usage in BUILD.bazel:

    load("//bazel:ttsim.bzl", "ttsim_test")

    ttsim_test(
        name = "api_noc_ttsim_wh",
        test = "//tests/tt_metal/tt_metal:api_test_noc",
        arch = "wormhole_b0",
        gtest_filter = "MeshDeviceFixture.IdleEthTestNocStreamRegs",
    )

These targets run with plain `bazel test ...` and appear alongside other
CPU-only tests. WH and BH variants run in parallel.

No CMake build is required — all firmware objects and linker scripts are
built by Bazel using the SFPI cross-compiler (via genrule in ttsim_runtime.bzl).
Source headers are accessed from the workspace via the no-sandbox tag.
"""

_ARCH_CONFIG = {
    "wormhole_b0": struct(
        ttsim_lib = "@ttsim_wh//file",
        soc_desc = "//tt_metal:soc_descriptors/wormhole_b0_80_arch.yaml",
        runtime = "//tests/ttsim:runtime_wh",
    ),
    "blackhole": struct(
        ttsim_lib = "@ttsim_bh//file",
        soc_desc = "//tt_metal:soc_descriptors/blackhole_140_arch.yaml",
        runtime = "//tests/ttsim:runtime_bh",
    ),
}

def ttsim_test(name, test, arch, gtest_filter = None, tags = [], size = "large", timeout = "long", **kwargs):
    """Create a test target that runs under the TTSim simulator.

    The generated target is a CPU-only test with no requires_* hardware tags,
    so it passes through the default tag filter and runs with `bazel test ...`.

    Args:
        name: Target name.
        test: Label of the underlying test target (cc_test or py_test).
        arch: Architecture to simulate ("wormhole_b0" or "blackhole").
        gtest_filter: Optional gtest filter pattern (e.g. "Fixture.Test").
            Only the matching test cases will run.
        tags: Additional Bazel tags (ttsim is always added).
        size: Bazel test size (default "large" since ttsim tests are slow).
        timeout: Bazel test timeout (default "long").
        **kwargs: Passed through to native.sh_test.
    """
    if arch not in _ARCH_CONFIG:
        fail("Unknown TTSim arch '{}'. Valid: {}".format(arch, _ARCH_CONFIG.keys()))

    cfg = _ARCH_CONFIG[arch]

    # Arguments to run_ttsim.sh:
    #   $1  rlocationpath to TTSim shared library
    #   $2  rlocationpath to SoC descriptor YAML
    #   $3  rlocationpath to test binary
    #   $4  rlocationpath to @sfpi g++ binary (to find SFPI root)
    #   $5  rlocationpath to runtime hw tree (firmware objects + linker scripts)
    #   $6+ forwarded to the test binary (e.g. --gtest_filter=...)
    test_args = [
        "$(rlocationpath {})".format(cfg.ttsim_lib),
        "$(rlocationpath {})".format(cfg.soc_desc),
        "$(rlocationpath {})".format(test),
        "$(rlocationpath @sfpi//:gxx)",
        "$(rlocationpath {})".format(cfg.runtime),
    ]
    if gtest_filter:
        test_args.append("--gtest_filter=" + gtest_filter)

    native.sh_test(
        name = name,
        srcs = ["//third_party/ttsim:run_ttsim.sh"],
        args = test_args,
        data = [
            test,
            cfg.ttsim_lib,
            cfg.soc_desc,
            "//tt_metal:core_descriptors",
            # Bazel-built runtime tree (firmware objects + linker scripts)
            cfg.runtime,
            # SFPI compiler — needed by JIT build at test runtime
            "@sfpi//:gxx",
            "@sfpi//:compiler_files",
        ],
        env = {
            "TTSIM_ARCH": arch,
        },
        # no-sandbox: the JIT build system reads source headers and kernel
        # files from the workspace at test time. Binary artifacts (firmware
        # objects, linker scripts, SFPI compiler) come from Bazel runfiles.
        tags = tags + ["ttsim", "no-sandbox"],
        size = size,
        timeout = timeout,
        **kwargs,
    )

def ttsim_test_suite(name, test, gtest_filter = None, tags = [], **kwargs):
    """Create WH and BH TTSim test variants for a single test target.

    Generates two targets: {name}_wh and {name}_bh that run in parallel.

    Args:
        name: Base name for the generated targets.
        test: Label of the underlying test target.
        gtest_filter: Optional gtest filter pattern passed to both variants.
        tags: Additional Bazel tags.
        **kwargs: Passed through to ttsim_test.
    """
    ttsim_test(
        name = name + "_wh",
        test = test,
        arch = "wormhole_b0",
        gtest_filter = gtest_filter,
        tags = tags,
        **kwargs,
    )
    ttsim_test(
        name = name + "_bh",
        test = test,
        arch = "blackhole",
        gtest_filter = gtest_filter,
        tags = tags,
        **kwargs,
    )
