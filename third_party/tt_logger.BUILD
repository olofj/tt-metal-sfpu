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
