#!/usr/bin/env python3
# SPDX-FileCopyrightText: (c) 2025 Tenstorrent Inc.
# SPDX-License-Identifier: Apache-2.0

"""Pytest wrapper for Bazel py_test targets.

Bazel's py_test does not natively understand pytest. This wrapper script
is used as the `main` entry point for all pytest_test() macro targets.
It configures the environment so that:

1. conftest.py files are discovered correctly despite Bazel's runfile layout
2. The workspace root is on sys.path so `from tests.xxx import ...` works
3. pytest is invoked with the correct arguments
"""

import os
import sys


def main():
    # Bazel sets TEST_SRCDIR to the runfiles root. The workspace root within
    # runfiles is at $TEST_SRCDIR/$TEST_WORKSPACE.
    test_srcdir = os.environ.get("TEST_SRCDIR", "")
    test_workspace = os.environ.get("TEST_WORKSPACE", "")

    if test_srcdir and test_workspace:
        workspace_root = os.path.join(test_srcdir, test_workspace)
    else:
        # Fallback: use BUILD_WORKSPACE_DIRECTORY if available (test --run_under),
        # or the current directory.
        workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY", os.getcwd())

    # Add workspace root to sys.path so that imports like
    # `from tests.ttnn.utils_for_testing import ...` resolve correctly.
    # This mimics the behavior of running pytest from the repo root.
    if workspace_root not in sys.path:
        sys.path.insert(0, workspace_root)

    # Set rootdir for conftest.py discovery. pytest walks up from the test
    # file looking for conftest.py; without --rootdir, Bazel's runfiles
    # directory structure confuses this search.
    args = sys.argv[1:]

    # Ensure rootdir is set. If the macro already passed --rootdir, this
    # is a no-op. Otherwise, default to the workspace root.
    has_rootdir = any(a.startswith("--rootdir") for a in args)
    if not has_rootdir:
        args = ["--rootdir", workspace_root] + args

    # Replace $$BUILD_WORKSPACE_DIRECTORY placeholder with actual path.
    # The Bazel macro uses $$ to escape the $ in .bzl files.
    args = [a.replace("$$BUILD_WORKSPACE_DIRECTORY", workspace_root) for a in args]

    # Import and run pytest.
    import pytest
    sys.exit(pytest.main(args))


if __name__ == "__main__":
    main()
