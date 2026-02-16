load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

# FlatBuffers v24.3.25 — C++ runtime and compiler.
# Avoids the rules_swift dependency that causes Bazel 9 compatibility issues.

cc_library(
    name = "flatbuffers",
    hdrs = glob(["include/flatbuffers/**/*.h"]),
    includes = ["include"],
    visibility = ["//visibility:public"],
)

cc_library(
    name = "flatc_lib",
    srcs = glob(
        [
            "src/*.cpp",
            "grpc/src/compiler/*.cc",
        ],
        exclude = [
            "src/flatc_main.cpp",
            "src/flathash.cpp",
        ],
    ),
    hdrs = glob([
        "include/flatbuffers/**/*.h",
        "src/*.h",
        "grpc/src/compiler/*.h",
    ]),
    copts = ["-Wno-sign-compare"],
    includes = [
        "grpc",
        "include",
        "src",
    ],
    visibility = ["//visibility:public"],
)

cc_binary(
    name = "flatc",
    srcs = ["src/flatc_main.cpp"],
    visibility = ["//visibility:public"],
    deps = [":flatc_lib"],
)
