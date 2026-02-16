"""Module extensions for dependencies not available on the Bazel Central Registry."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//toolchain/sfpi:repo.bzl", "sfpi_toolchain_repo")

def _non_bcr_deps_impl(module_ctx):
    # Protocol Buffers v21.12 — NOT using BCR because transitive deps
    # (google_benchmark → googletest) pull protobuf to v29+ which drags
    # in abseil/zlib. CMake build pins to v21.12 via CPM.
    # Custom build_file because upstream BUILD.bazel uses WORKSPACE-only deps.
    http_archive(
        name = "protobuf",
        urls = ["https://github.com/protocolbuffers/protobuf/archive/refs/tags/v21.12.tar.gz"],
        strip_prefix = "protobuf-21.12",
        build_file = "//third_party:protobuf.BUILD",
    )

    # Cap'n Proto v1.2.0
    # Has native Bazel build files in c++/ subdirectory.
    # The capnproto_capture_this.patch from CMake is only needed for the
    # [=] -> [=, this] C++20 fix, which the Bazel build handles via compiler flags.
    http_archive(
        name = "capnproto",
        urls = ["https://github.com/capnproto/capnproto/archive/d135c9ca5e15219eaf131dfce1a41afdbaea9aab.tar.gz"],
        strip_prefix = "capnproto-d135c9ca5e15219eaf131dfce1a41afdbaea9aab/c++",
        # sha256 should be added after first successful fetch
    )

    # nanobind v2.10.2 — Python bindings
    http_archive(
        name = "nanobind",
        urls = ["https://github.com/wjakob/nanobind/archive/c5a3a378aa61d104c82ca053cb1e367782cd3618.tar.gz"],
        strip_prefix = "nanobind-c5a3a378aa61d104c82ca053cb1e367782cd3618",
        build_file = "//third_party:nanobind.BUILD",
    )

    # xtl 0.8.0 — header-only support library for xtensor
    http_archive(
        name = "xtl",
        urls = ["https://github.com/xtensor-stack/xtl/archive/refs/tags/0.8.0.tar.gz"],
        strip_prefix = "xtl-0.8.0",
        build_file = "//third_party:xtl.BUILD",
    )

    # xtensor 0.26.0 — header-only tensor library
    http_archive(
        name = "xtensor",
        urls = ["https://github.com/xtensor-stack/xtensor/archive/refs/tags/0.26.0.tar.gz"],
        strip_prefix = "xtensor-0.26.0",
        build_file = "//third_party:xtensor.BUILD",
    )

    # xtensor-blas 0.22.0 — BLAS bindings for xtensor
    http_archive(
        name = "xtensor_blas",
        urls = ["https://github.com/xtensor-stack/xtensor-blas/archive/refs/tags/0.22.0.tar.gz"],
        strip_prefix = "xtensor-blas-0.22.0",
        build_file = "//third_party:xtensor_blas.BUILD",
    )

    # simde v0.8.2 — SIMD Everywhere, header-only
    http_archive(
        name = "simde",
        urls = ["https://github.com/simd-everywhere/simde/archive/refs/tags/v0.8.2.tar.gz"],
        strip_prefix = "simde-0.8.2",
        build_file = "//third_party:simde.BUILD",
    )

    # Taskflow v3.7.0 — header-only task-parallel library
    http_archive(
        name = "taskflow",
        urls = ["https://github.com/taskflow/taskflow/archive/refs/tags/v3.7.0.tar.gz"],
        strip_prefix = "taskflow-3.7.0",
        build_file = "//third_party:taskflow.BUILD",
    )

    # boost-ext reflect v1.2.6 — single-header reflection
    http_archive(
        name = "reflect",
        urls = ["https://github.com/boost-ext/reflect/archive/refs/tags/v1.2.6.tar.gz"],
        strip_prefix = "reflect-1.2.6",
        build_file = "//third_party:reflect.BUILD",
    )

    # enchantum — TT-used fork of magic_enum
    http_archive(
        name = "enchantum",
        urls = ["https://github.com/ZXShady/enchantum/archive/8ca5b0eb7e7ebe0252e5bc6915083f1dd1b8294e.tar.gz"],
        strip_prefix = "enchantum-8ca5b0eb7e7ebe0252e5bc6915083f1dd1b8294e",
        build_file = "//third_party:enchantum.BUILD",
    )

    # tt-logger 1.1.7 — Tenstorrent logging library
    http_archive(
        name = "tt_logger",
        urls = ["https://github.com/tenstorrent/tt-logger/archive/refs/tags/v1.1.7.tar.gz"],
        strip_prefix = "tt-logger-1.1.7",
        build_file = "//third_party:tt_logger.BUILD",
    )

    # FlatBuffers 24.3.25 — C++ runtime and flatc compiler.
    # The BCR module depends on rules_swift which conflicts with Bazel 9.
    # patch_cmds removes sub-package BUILD files so our overlay BUILD can
    # glob sources from src/ and grpc/src/compiler/.
    http_archive(
        name = "flatbuffers",
        urls = ["https://github.com/google/flatbuffers/archive/refs/tags/v24.3.25.tar.gz"],
        strip_prefix = "flatbuffers-24.3.25",
        build_file = "//third_party:flatbuffers.BUILD",
        patch_cmds = [
            "find . -mindepth 2 -name BUILD.bazel -delete",
            "find . -mindepth 2 -name BUILD -delete",
        ],
    )

    # picosha2 v1.0.1 — header-only SHA256 library (used by UMD)
    http_archive(
        name = "picosha2",
        urls = ["https://github.com/okdshin/PicoSHA2/archive/refs/tags/v1.0.1.tar.gz"],
        strip_prefix = "PicoSHA2-1.0.1",
        build_file = "//third_party:picosha2.BUILD",
    )

    # Standalone ASIO asio-1-30-2 — header-only async I/O (used by UMD)
    http_archive(
        name = "asio",
        urls = ["https://github.com/chriskohlhoff/asio/archive/refs/tags/asio-1-30-2.tar.gz"],
        strip_prefix = "asio-asio-1-30-2",
        build_file = "//third_party:asio.BUILD",
    )

non_bcr_deps = module_extension(
    implementation = _non_bcr_deps_impl,
)

# ===========================================================================
# SFPI RISC-V cross-compilation toolchain
# ===========================================================================

def _sfpi_ext_impl(module_ctx):
    sfpi_toolchain_repo(name = "sfpi")

sfpi_ext = module_extension(
    implementation = _sfpi_ext_impl,
)
