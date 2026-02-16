load("@rules_cc//cc:cc_library.bzl", "cc_library")

# FlatBuffers — C++ runtime only (no Swift/Java/etc.)
# Avoids the rules_swift dependency that causes Bazel 9 compatibility issues.

cc_library(
    name = "flatbuffers",
    hdrs = glob(["include/flatbuffers/**/*.h"]),
    includes = ["include"],
    visibility = ["//visibility:public"],
)
