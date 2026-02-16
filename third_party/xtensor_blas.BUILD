load("@rules_cc//cc:cc_library.bzl", "cc_library")

cc_library(
    name = "xtensor_blas",
    hdrs = glob([
        "include/xflens/**/*.h",
        "include/xtensor-blas/**/*.hpp",
    ]),
    includes = ["include"],
    deps = ["@xtensor//:xtensor"],
    visibility = ["//visibility:public"],
)
