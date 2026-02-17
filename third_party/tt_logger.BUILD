load("@rules_cc//cc:cc_library.bzl", "cc_library")

cc_library(
    name = "tt_logger",
    hdrs = glob(["include/tt-logger/**/*.hpp"]),
    includes = ["include"],
    deps = [
        "@fmt",
        "@spdlog",
    ],
    visibility = ["//visibility:public"],
)

# Headers for .deb packaging (metalium-dev).
# Mirrors CMake FILE_SET api on the tt-logger target.
filegroup(
    name = "deb_headers",
    srcs = glob(["include/tt-logger/**/*.hpp"]),
    visibility = ["//visibility:public"],
)
