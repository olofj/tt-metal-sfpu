load("@rules_cc//cc:cc_library.bzl", "cc_library")

cc_library(
    name = "enchantum",
    hdrs = glob(["enchantum/include/enchantum/**/*.hpp"]),
    includes = ["enchantum/include"],
    visibility = ["//visibility:public"],
)

# Headers for .deb packaging (metalium-dev).
# Mirrors CMake install(DIRECTORY enchantum/include/ ...) from upstream.
filegroup(
    name = "deb_headers",
    srcs = glob(["enchantum/include/enchantum/**/*.hpp"]),
    visibility = ["//visibility:public"],
)
