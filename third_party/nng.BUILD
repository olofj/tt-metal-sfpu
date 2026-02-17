load("@rules_cc//cc:cc_library.bzl", "cc_library")

# nng (nanomsg-next-gen) v1.8.0 — lightweight messaging library.
# Used by the UMD simulation subsystem.
#
# Upstream uses CMake with extensive feature detection; this BUILD file
# provides a static Bazel build targeting Linux/x86_64 with epoll.
# All standard SP protocols and the TCP/IPC/inproc transports are enabled.
# TLS, WebSocket, and ZeroTier transports are disabled (not needed).

# ---------------------------------------------------------------------------
# Compile definitions — mirrors CMake config for Linux x86_64
# ---------------------------------------------------------------------------
_DEFINES = [
    # Static library build
    "NNG_STATIC_LIB",

    # Platform detection
    "NNG_PLATFORM_POSIX",
    "NNG_PLATFORM_LINUX",

    # POSIX feature-test macros (set by upstream for glibc compatibility)
    "_GNU_SOURCE",
    "_REENTRANT",
    "_THREAD_SAFE",
    "_POSIX_PTHREAD_SEMANTICS",

    # Linux capabilities detected by CMake's check_symbol_exists / check_func
    "NNG_HAVE_EPOLL",
    "NNG_HAVE_EPOLL_CREATE1",
    "NNG_HAVE_EVENTFD",
    "NNG_HAVE_GETRANDOM",
    "NNG_HAVE_CLOCK_GETTIME",
    "NNG_HAVE_LOCKF",
    "NNG_HAVE_UNIX_SOCKETS",
    "NNG_HAVE_SOCKETPAIR",
    "NNG_HAVE_SEMAPHORE_PTHREAD",
    "NNG_HAVE_PTHREAD_ATFORK_PTHREAD",
    "NNG_HAVE_PTHREAD_SETNAME_NP",
    "NNG_HAVE_ABSTRACT_SOCKETS",
    "NNG_HAVE_MSG_CONTROL",
    "NNG_HAVE_SOPEERCRED",
    "NNG_HAVE_BACKTRACE",
    "NNG_HAVE_STDATOMIC",
    "NNG_HAVE_STRNLEN",
    "NNG_HAVE_STRCASECMP",
    "NNG_HAVE_STRNCASECMP",
    "NNG_HAVE_LOCALTIME_R",
    "NNG_HAVE_INET6",
    "NNG_HAVE_TIMESPEC_GET",

    # Transports
    "NNG_TRANSPORT_TCP",
    "NNG_TRANSPORT_IPC",
    "NNG_TRANSPORT_INPROC",
    "NNG_TRANSPORT_FDC",

    # Protocols — NNG_HAVE_* are the internal flags set by nng_defines_if()
    "NNG_HAVE_BUS0",
    "NNG_HAVE_PAIR0",
    "NNG_HAVE_PAIR1",
    "NNG_HAVE_PUSH0",
    "NNG_HAVE_PULL0",
    "NNG_HAVE_PUB0",
    "NNG_HAVE_SUB0",
    "NNG_HAVE_REQ0",
    "NNG_HAVE_REP0",
    "NNG_HAVE_SURVEYOR0",
    "NNG_HAVE_RESPONDENT0",

    # Supplemental features
    "NNG_SUPP_HTTP",
    "NNG_SUPP_BASE64",
    "NNG_SUPP_SHA1",
]

_COPTS = [
    # Force C compilation — the Bazel toolchain routes .c files through clang++.
    "-x",
    "c",
    "-std=c17",
    "-Wno-unused-function",
    "-Wno-unused-parameter",
]

cc_library(
    name = "nng",
    srcs = glob(
        [
            "src/**/*.c",
            "src/**/*.h",
        ],
        exclude = [
            # Test files and infrastructure
            "src/**/*_test.c",
            "src/testing/**",
            "src/tools/**",

            # Compat layer (nanomsg API shim — not needed)
            "src/compat/**",

            # Windows platform (we only build for Linux)
            "src/platform/windows/**",

            # POSIX poll backends we don't use on Linux (epoll is selected)
            "src/platform/posix/posix_pollq_kqueue.c",
            "src/platform/posix/posix_pollq_poll.c",
            "src/platform/posix/posix_pollq_port.c",

            # Random backends we don't use on Linux (getrandom is selected)
            "src/platform/posix/posix_rand_arc4random.c",
            "src/platform/posix/posix_rand_urandom.c",

            # Transports we don't build (require TLS/WS/ZeroTier deps)
            "src/sp/transport/tls/**",
            "src/sp/transport/ws/**",
            "src/sp/transport/zerotier/**",

            # TLS engine implementations (we keep only tls_common.c stub)
            "src/supplemental/tls/mbedtls/**",
            "src/supplemental/tls/wolfssl/**",

            # WebSocket full implementation (use stub.c instead)
            "src/supplemental/websocket/websocket.c",
        ],
    ),
    hdrs = glob(["include/**/*.h"]),
    copts = _COPTS,
    defines = _DEFINES,
    includes = [
        "include",
        "src",
    ],
    linkopts = [
        "-lpthread",
        "-lrt",
    ],
    strip_include_prefix = "include",
    visibility = ["//visibility:public"],
)
