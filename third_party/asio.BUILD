load("@rules_cc//cc:cc_library.bzl", "cc_library")

# Standalone ASIO — header-only async I/O library (non-Boost)
cc_library(
    name = "asio",
    hdrs = glob(["asio/include/**/*.hpp", "asio/include/**/*.ipp"]),
    defines = [
        "ASIO_STANDALONE",
        "ASIO_NO_DEPRECATED",
    ],
    includes = ["asio/include"],
    visibility = ["//visibility:public"],
)
