load("@rules_cc//cc:cc_library.bzl", "cc_library")

cc_library(
    name = "nanobind",
    hdrs = glob(["include/nanobind/**/*.h"]),
    srcs = glob(["src/*.cpp", "src/*.h"]),
    includes = ["include"],
    visibility = ["//visibility:public"],
)
