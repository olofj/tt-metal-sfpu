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


def _resolve_source_root(workspace_root):
    """Resolve the real source tree path from Bazel runfiles symlinks.

    In Bazel's runfiles tree, files are symlinks to the real source tree.
    For hardware tests that need JIT firmware compilation, we need the real
    source tree path (which has firmware .cc sources, runtime/hw/lib/, etc.)
    rather than the runfiles path (which only has declared data deps).

    Returns the real source root, or None if it cannot be determined.
    """
    # Try resolving a known file to find the real source tree.
    for probe in ("conftest.py", "BUILD.bazel", "MODULE.bazel"):
        probe_path = os.path.join(workspace_root, probe)
        if os.path.islink(probe_path):
            real_path = os.path.realpath(probe_path)
            return os.path.dirname(real_path)

    # Fallback: walk up from workspace_root looking for a directory that
    # contains both tt_metal/ and runtime/ (i.e., a populated source tree).
    candidate = workspace_root
    for _ in range(10):
        candidate = os.path.dirname(candidate)
        if not candidate or candidate == os.path.dirname(candidate):
            break
        if (os.path.isdir(os.path.join(candidate, "tt_metal", "hw", "firmware")) and
                os.path.isfile(os.path.join(candidate, "conftest.py"))):
            return candidate

    return None


class _SourceTreePathExtender:
    """MetaPathFinder that extends package __path__ to include source tree dirs.

    When a top-level package (e.g. models/) is found in the Bazel runfiles tree
    first, Python won't search other sys.path entries for sub-packages.  This
    finder is installed at position 0 in sys.meta_path and, for every import of
    a dotted name (A.B), checks whether the parent package A already has its
    __path__ extended.  If not, it appends the source-tree directory so that the
    standard PathFinder can locate the sub-package.

    It always returns None — the actual loading is delegated to the default
    import machinery, which now sees the extended __path__.
    """

    def __init__(self, source_root):
        self._source_root = source_root
        self._extended = set()

    def find_spec(self, fullname, path=None, target=None):
        parts = fullname.split(".")
        if len(parts) < 2:
            return None

        parent_name = ".".join(parts[:-1])
        if parent_name in self._extended:
            return None

        parent = sys.modules.get(parent_name)
        if parent is None or not hasattr(parent, "__path__"):
            return None

        source_parent_dir = os.path.join(self._source_root, *parts[:-1])
        if os.path.isdir(source_parent_dir) and source_parent_dir not in parent.__path__:
            parent.__path__.append(source_parent_dir)
            self._extended.add(parent_name)

        return None


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

    # Bazel's test harness sets HOME to a non-writable temp directory.
    # The _ttnn.so native module segfaults during initialization when HOME
    # doesn't exist (likely from UMD driver or hwloc library trying to read
    # config files from HOME). Ensure HOME points to a writable directory.
    home = os.environ.get("HOME", "")
    if not home or not os.path.isdir(home):
        os.environ["HOME"] = os.environ.get("TEST_TMPDIR", "/tmp")

    # Ensure TT_METAL_RUNTIME_ROOT is set before any native module is loaded.
    # In Bazel's sandbox the CWD-based fallback in rtoptions.cpp fails because
    # the sandbox directory does not contain a tt_metal/ subdirectory.
    #
    # For hardware tests (--strategy=TestRunner=local), resolve symlinks from
    # the runfiles tree to find the real source tree. JIT firmware compilation
    # needs access to firmware .cc sources, headers, and runtime/hw/lib/ which
    # are not declared as Bazel data deps.
    source_root = _resolve_source_root(workspace_root)
    if source_root and os.path.isdir(os.path.join(source_root, "tt_metal", "hw", "firmware")):
        os.environ.setdefault("TT_METAL_RUNTIME_ROOT", source_root)
    else:
        os.environ.setdefault("TT_METAL_RUNTIME_ROOT", workspace_root)

    # Add workspace root to sys.path so that imports like
    # `from tests.ttnn.utils_for_testing import ...` resolve correctly.
    # This mimics the behavior of running pytest from the repo root.
    if workspace_root not in sys.path:
        sys.path.insert(0, workspace_root)

    # For local-strategy tests (hardware tests), also add the resolved source
    # root to sys.path. Test modules may import from packages that aren't
    # declared as Bazel deps (e.g., model utilities). The source root has the
    # full source tree, while the runfiles tree only contains declared deps.
    if source_root and source_root != workspace_root and source_root not in sys.path:
        sys.path.insert(1, source_root)
        # Install a meta-path finder that extends package __path__ on demand.
        # When a top-level package (e.g. models/) exists in both the runfiles
        # tree and the source tree, Python only searches the first directory
        # it finds. This finder adds the source tree directory to the parent
        # package's __path__ so sub-packages (e.g. models.demos.bert) that
        # only exist in the source tree can still be found.
        sys.meta_path.insert(0, _SourceTreePathExtender(source_root))

    # Set rootdir for conftest.py discovery. pytest walks up from the test
    # file looking for conftest.py; without --rootdir, Bazel's runfiles
    # directory structure confuses this search.
    args = sys.argv[1:]

    # Ensure rootdir is set. If the macro already passed --rootdir, this
    # is a no-op. Otherwise, default to the workspace root.
    has_rootdir = any(a.startswith("--rootdir") for a in args)
    if not has_rootdir:
        args = ["--rootdir", workspace_root] + args

    # Replace $BUILD_WORKSPACE_DIRECTORY placeholder with actual path.
    # The Bazel macro uses $$ in .bzl to produce a literal $ in the arg.
    args = [a.replace("$BUILD_WORKSPACE_DIRECTORY", workspace_root) for a in args]

    # Import and run pytest.
    import pytest
    ret = pytest.main(args)

    # Flush output before exiting — os._exit() skips buffer flushing.
    sys.stdout.flush()
    sys.stderr.flush()

    # Use os._exit() to avoid nanobind's leak-detection abort.
    # The _ttnn.so extension is compiled with NB_ABORT_ON_LEAK, which calls
    # abort() during interpreter shutdown when types/functions are still
    # referenced. This is a known benign condition (the types are alive
    # because the module is still loaded) but it causes Bazel to report
    # FAIL even when all tests pass.  os._exit() bypasses interpreter
    # cleanup entirely, matching the pattern used in tools/triage/triage.py.
    os._exit(ret)


if __name__ == "__main__":
    main()
