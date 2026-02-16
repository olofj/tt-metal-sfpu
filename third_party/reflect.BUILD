load("@rules_cc//cc:cc_library.bzl", "cc_library")

# The header file is named "reflect" (no extension). A cc_library target
# cannot share the same name as a source file in Bazel, so the library is
# named "reflect_lib". Consumers use @reflect//:reflect_lib.
cc_library(
    name = "reflect_lib",
    hdrs = ["reflect"],
    includes = ["."],
    visibility = ["//visibility:public"],
)
