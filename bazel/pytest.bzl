"""Bazel macro for running pytest-based Python tests.

Wraps native py_test to provide pytest runner configuration, marker-to-tag
mapping, and automatic conftest.py discovery. This enables Bazel's
affected-target analysis (bazel query rdeps) to determine which Python
tests to run when source code changes.

Usage in BUILD.bazel:

    load("//bazel:pytest.bzl", "pytest_test")

    pytest_test(
        name = "test_reshape",
        srcs = ["test_reshape.py"],
        deps = ["//ttnn/ttnn:ttnn_py"],
        markers = ["post_commit"],
    )
"""

load("@rules_python//python:py_test.bzl", "py_test")

# Map pytest markers (from pytest.ini) to Bazel tags.
# Additional tags like "slow" also influence size/timeout.
_MARKER_TO_TAGS = {
    "post_commit": ["post_commit"],
    "frequent": ["frequent"],
    "slow": ["slow"],
    "skip_post_commit": ["skip_post_commit"],
    "frequently_hangs": ["frequently_hangs", "no_remote"],
    "eager_host_side": ["eager_host_side"],
    "eager_package_silicon": ["eager_package_silicon"],
    "models_performance_bare_metal": ["perf_bare_metal"],
    "models_performance_virtual_machine": ["perf_vm"],
    "models_device_performance_bare_metal": ["perf_device_bare_metal"],
    "model_perf_t3000": ["perf_t3000"],
    "model_perf_tg": ["perf_tg"],
    "requires_fast_runtime_mode_off": ["requires_fast_runtime_mode_off"],
}

def pytest_test(
        name,
        srcs,
        deps = [],
        data = [],
        markers = [],
        timeout_seconds = 300,
        tags = [],
        env = {},
        **kwargs):
    """Run a Python test file through pytest inside Bazel.

    Args:
        name: Target name (conventionally the test filename without .py).
        srcs: Test source files (typically one test_*.py file).
        deps: Python library dependencies.
        data: Data files needed at runtime (model weights, configs, etc.).
        markers: pytest markers from pytest.ini (e.g., ["post_commit", "slow"]).
            These are mapped to Bazel tags for test_tag_filters.
        timeout_seconds: pytest-timeout value in seconds (default 300, matches
            pytest.ini). Also used to select Bazel size/timeout.
        tags: Additional Bazel tags (merged with marker-derived tags).
        env: Environment variables to set for the test.
        **kwargs: Passed through to native py_test.
    """

    # Collect all Bazel tags from markers + explicit tags.
    all_tags = list(tags)
    for marker in markers:
        all_tags.extend(_MARKER_TO_TAGS.get(marker, [marker]))

    # Deduplicate while preserving order.
    seen = {}
    unique_tags = []
    for tag in all_tags:
        if tag not in seen:
            seen[tag] = True
            unique_tags.append(tag)

    # Select Bazel size/timeout based on test characteristics.
    # Bazel timeout limits: short=60s, moderate=300s, long=900s, eternal=3600s.
    if "slow" in unique_tags or timeout_seconds > 300:
        size = "large"
        timeout = "long"
    elif timeout_seconds > 60:
        size = "medium"
        timeout = "moderate"
    else:
        size = "small"
        timeout = "short"

    # Performance tests can run 30+ minutes.
    perf_tags = ["perf_bare_metal", "perf_vm", "perf_device_bare_metal", "perf_t3000", "perf_tg"]
    has_perf_tag = False
    for t in perf_tags:
        if t in unique_tags:
            has_perf_tag = True
    if has_perf_tag:
        size = "enormous"
        timeout = "eternal"

    # All pytest tests depend on conftest files and the pytest runner.
    all_data = list(data) + [
        "//tests/ttnn:conftest_files",
    ]

    # Core test deps: pytest runner, timeout plugin, and ttnn.
    all_deps = list(deps) + [
        "@pip//pytest",
        "@pip//pytest_timeout",
    ]

    # pytest args: match pytest.ini settings.
    # --rootdir ensures conftest.py discovery starts from the workspace root.
    # --override-ini sets timeout to match the requested value.
    pytest_args = [
        "--import-mode=importlib",
        "-vvs",
        "--timeout=%d" % timeout_seconds,
        "--rootdir=$$BUILD_WORKSPACE_DIRECTORY",
        "--override-ini=empty_parameter_set_mark=skip",
    ] + ["$(location %s)" % s for s in srcs]

    py_test(
        name = name,
        srcs = ["//bazel:pytest_wrapper.py"] + srcs,
        main = "//bazel:pytest_wrapper.py",
        args = pytest_args,
        deps = all_deps,
        data = all_data,
        tags = unique_tags,
        size = size,
        timeout = timeout,
        env = env,
        **kwargs
    )

def pytest_suite(name, srcs, deps = [], data = [], markers = [], tags = [], **kwargs):
    """Generate one pytest_test per test file, plus a test_suite grouping them.

    Convenience macro for directories with many test files that share the
    same deps/markers. Each test_*.py file becomes an individual py_test
    target for maximum affected-target granularity.

    Args:
        name: Suite name (used as the test_suite target name).
        srcs: List of test_*.py files (use glob(["test_*.py"])).
        deps: Shared deps for all tests.
        data: Shared data files for all tests.
        markers: Shared markers for all tests.
        tags: Shared tags for all tests.
        **kwargs: Passed through to each pytest_test.
    """
    test_names = []
    for src in srcs:
        test_name = src.replace(".py", "")
        test_names.append(test_name)
        pytest_test(
            name = test_name,
            srcs = [src],
            deps = deps,
            data = data,
            markers = markers,
            tags = tags,
            **kwargs
        )

    native.test_suite(
        name = name,
        tests = [":%s" % t for t in test_names],
        tags = tags,
    )
