# SPDX-FileCopyrightText: (c) 2025 Tenstorrent AI ULC
#
# SPDX-License-Identifier: Apache-2.0

"""Sphinx documentation builder for Bazel integration.

Invoked as a py_binary by Bazel genrule targets. Runs sphinx-build for
either the tt-metalium or ttnn documentation sub-project, mirroring the
behaviour of the docs/Makefile.

Usage:
    python sphinx_build.py --project=tt-metalium --srcdir=source/tt-metalium \
        --outdir=build/tt-metalium [--doxygen-xml=doxygen_build/xml] \
        [--docs-version=latest]
"""

import argparse
import os
import sys


def main():
    parser = argparse.ArgumentParser(description="Build Sphinx documentation")
    parser.add_argument("--project", required=True, choices=["tt-metalium", "ttnn"])
    parser.add_argument("--srcdir", required=True, help="Sphinx source directory")
    parser.add_argument("--outdir", required=True, help="Sphinx output directory")
    parser.add_argument("--docs-version", default="latest", help="Documentation version string")
    args = parser.parse_args()

    # Set environment variables expected by docs/source/conf.py
    os.environ["REQUESTED_DOCS_PKG"] = args.project
    os.environ["DOCS_VERSION"] = args.docs_version

    # Disable fast_runtime_mode for TTNN so autodoc can load docstrings
    if args.project == "ttnn":
        os.environ["TTNN_CONFIG_OVERRIDES"] = '{"enable_fast_runtime_mode": false}'

    # Run sphinx-build
    from sphinx.cmd.build import main as sphinx_main

    sys.exit(sphinx_main([
        "-W",           # turn warnings into errors (matches Makefile SPHINXOPTS)
        args.srcdir,    # source directory
        args.outdir,    # output directory
    ]))


if __name__ == "__main__":
    main()
