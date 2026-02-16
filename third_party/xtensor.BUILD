load("@rules_cc//cc:cc_library.bzl", "cc_library")

cc_library(
    name = "xtensor",
    hdrs = glob(["include/xtensor/**/*.hpp"]),
    includes = ["include"],
    deps = ["@xtl//:xtl"],
    visibility = ["//visibility:public"],
)
