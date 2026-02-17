load("@rules_cc//cc:cc_library.bzl", "cc_library")

# libuv v1.51.0 — cross-platform async I/O library.
# Used by the UMD simulation subsystem.
#
# Upstream uses CMake; this BUILD file provides a static Bazel build
# targeting Linux/x86_64. Only common + Unix + Linux-specific sources
# are compiled (no Windows, macOS, BSDs, etc.).

# ---------------------------------------------------------------------------
# Common (platform-independent) sources
# ---------------------------------------------------------------------------
_COMMON_SRCS = [
    "src/fs-poll.c",
    "src/idna.c",
    "src/inet.c",
    "src/random.c",
    "src/strscpy.c",
    "src/strtok.c",
    "src/thread-common.c",
    "src/threadpool.c",
    "src/timer.c",
    "src/uv-common.c",
    "src/uv-data-getter-setters.c",
    "src/version.c",
]

# ---------------------------------------------------------------------------
# Unix sources (shared across all Unix-like platforms)
# ---------------------------------------------------------------------------
_UNIX_SRCS = [
    "src/unix/async.c",
    "src/unix/core.c",
    "src/unix/dl.c",
    "src/unix/fs.c",
    "src/unix/getaddrinfo.c",
    "src/unix/getnameinfo.c",
    "src/unix/loop.c",
    "src/unix/loop-watcher.c",
    "src/unix/pipe.c",
    "src/unix/poll.c",
    "src/unix/process.c",
    "src/unix/random-devurandom.c",
    "src/unix/signal.c",
    "src/unix/stream.c",
    "src/unix/tcp.c",
    "src/unix/thread.c",
    "src/unix/tty.c",
    "src/unix/udp.c",
]

# ---------------------------------------------------------------------------
# Linux-specific sources
# ---------------------------------------------------------------------------
_LINUX_SRCS = [
    "src/unix/linux.c",
    "src/unix/procfs-exepath.c",
    "src/unix/proctitle.c",  # APPLE or Android|Linux
    "src/unix/random-getrandom.c",
    "src/unix/random-sysctl-linux.c",
]

cc_library(
    name = "libuv",
    srcs = _COMMON_SRCS + _UNIX_SRCS + _LINUX_SRCS + glob([
        "src/*.h",
        "src/unix/*.h",
    ]),
    hdrs = glob(["include/**/*.h"]),
    copts = [
        # Force C compilation — the Bazel toolchain routes .c files through clang++.
        "-x",
        "c",
        "-std=gnu11",
        "-Wno-unused-parameter",
    ],
    defines = [
        "_GNU_SOURCE",
        "_POSIX_C_SOURCE=200112",
        "_FILE_OFFSET_BITS=64",
        "_LARGEFILE_SOURCE",
    ],
    includes = [
        "include",
        "src",
    ],
    linkopts = [
        "-lpthread",
        "-ldl",
        "-lrt",
    ],
    strip_include_prefix = "include",
    visibility = ["//visibility:public"],
)
