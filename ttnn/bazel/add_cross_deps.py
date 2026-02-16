#!/usr/bin/env python3
"""Add cross-operation extra_deps to BUILD.bazel files.

Reads the dependency map and updates each operation's BUILD.bazel to include
extra_deps pointing to the _hdrs targets of its dependencies.
"""

import re
import sys
from pathlib import Path

OPS_ROOT = Path("ttnn/cpp/ttnn/operations")

# Cross-operation dependencies (from analysis of .cpp includes)
DEPENDENCIES = {
    "ccl": ['core', 'data_movement', 'experimental/ccl', 'full', 'reduction', 'transformer'],
    "conv": ['core', 'data_movement', 'eltwise/binary', 'eltwise/unary', 'matmul', 'sliding_window'],
    "core": ['data_movement', 'experimental/reshape'],
    "data_movement": ['ccl', 'core', 'experimental/reshape', 'full', 'reduction', 'sliding_window'],
    "debug": ['data_movement'],
    "eltwise/binary": ['core', 'data_movement', 'eltwise/binary_ng', 'eltwise/ternary', 'eltwise/unary', 'matmul'],
    "eltwise/binary_backward": ['data_movement', 'eltwise/binary', 'eltwise/complex_unary', 'eltwise/ternary', 'eltwise/ternary_backward', 'eltwise/unary', 'eltwise/unary_backward'],
    "eltwise/binary_ng": ['eltwise/binary', 'eltwise/unary'],
    "eltwise/complex_binary": ['eltwise/binary', 'eltwise/complex', 'eltwise/complex_unary', 'eltwise/unary'],
    "eltwise/complex_unary": ['data_movement', 'eltwise/binary', 'eltwise/complex'],
    "eltwise/complex_unary_backward": ['eltwise/binary', 'eltwise/complex', 'eltwise/complex_binary', 'eltwise/complex_unary', 'eltwise/ternary'],
    "eltwise/quantization": ['data_movement', 'eltwise/binary', 'eltwise/binary_ng', 'eltwise/unary'],
    "eltwise/ternary": ['data_movement', 'eltwise/binary', 'eltwise/binary_ng', 'eltwise/unary'],
    "eltwise/ternary_backward": ['data_movement', 'eltwise/binary', 'eltwise/ternary', 'eltwise/unary'],
    "eltwise/unary": ['core', 'data_movement', 'eltwise/binary', 'eltwise/complex', 'eltwise/complex_unary', 'eltwise/ternary', 'reduction'],
    "eltwise/unary_backward": ['data_movement', 'eltwise/binary', 'eltwise/binary_backward', 'eltwise/complex', 'eltwise/complex_binary', 'eltwise/complex_unary', 'eltwise/ternary', 'eltwise/unary', 'moreh', 'reduction'],
    "embedding": ['core', 'data_movement'],
    "embedding_backward": ['core'],
    "experimental/adaptive_pool": ['core', 'pool'],
    "experimental/bcast_to": ['core'],
    "experimental/ccl": ['ccl', 'core', 'data_movement', 'eltwise/unary', 'experimental/minimal_matmul', 'matmul', 'moreh', 'reduction'],
    "experimental/cnn": ['data_movement'],
    "experimental/conv3d": ['core', 'data_movement'],
    "experimental/copy": ['data_movement'],
    "experimental/isin": ['core'],
    "experimental/matmul": ['core'],
    "experimental/minimal_matmul": ['core', 'eltwise/unary', 'experimental/ccl'],
    "experimental/padded_slice": ['core', 'data_movement', 'experimental/reshape'],
    "experimental/paged_cache": ['core'],
    "experimental/plusone": ['core'],
    "experimental/reduction": ['core', 'moreh', 'reduction'],
    "experimental/reshape": ['data_movement'],
    "experimental/slice_write": ['core', 'data_movement', 'experimental/padded_slice'],
    "experimental/test": ['core'],
    "experimental/transformer": ['ccl', 'core', 'data_movement', 'normalization', 'reduction'],
    "full": ['moreh'],
    "kv_cache": ['core'],
    "loss": ['eltwise/binary', 'eltwise/unary', 'reduction'],
    "matmul": ['ccl', 'data_movement', 'eltwise/binary', 'eltwise/unary', 'kernel_helper_functions'],
    "moreh": ['core', 'eltwise/binary', 'experimental/reshape', 'reduction'],
    "normalization": ['core', 'data_movement', 'eltwise/binary', 'eltwise/binary_ng', 'eltwise/unary', 'moreh', 'reduction'],
    "point_to_point": ['ccl', 'data_movement'],
    "pool": ['conv', 'core', 'data_movement', 'experimental/reshape', 'reduction', 'sliding_window'],
    "prefetcher": ['ccl'],
    "rand": ['core'],
    "reduction": ['core', 'data_movement', 'eltwise/binary', 'eltwise/unary', 'eltwise/unary_backward', 'experimental/reduction', 'moreh', 'transformer'],
    "sliding_window": ['conv', 'core', 'data_movement', 'experimental/padded_slice', 'experimental/slice_write'],
    "transformer": ['ccl', 'core', 'data_movement', 'eltwise/binary', 'experimental/ccl', 'experimental/reshape', 'experimental/transformer', 'normalization'],
}

# Operations that don't have their own Bazel package (served by ttnn_core)
# The 'copy' operation is a subdir of data_movement with no BUILD.bazel
NON_PACKAGE_OPS = {"copy"}

# Operations with manually written BUILD.bazel that handle deps differently
MANUAL_OPS = {"core"}


def dep_to_label(dep_op: str) -> str:
    """Convert an operation path to a Bazel _hdrs label."""
    target_name = Path(dep_op).name
    return f"//ttnn/cpp/ttnn/operations/{dep_op}:{target_name}_hdrs"


def update_build_file(op_path: str, deps: list[str]):
    """Update a BUILD.bazel file to include extra_deps."""
    build_file = OPS_ROOT / op_path / "BUILD.bazel"
    if not build_file.exists():
        print(f"  SKIP {op_path}: no BUILD.bazel", file=sys.stderr)
        return False

    content = build_file.read_text()

    # Filter out non-package deps and self
    bazel_deps = []
    for dep in deps:
        if dep in NON_PACKAGE_OPS:
            continue  # Served by ttnn_core
        if dep == op_path:
            continue  # Self-dep
        # kernel_helper_functions uses a plain cc_library, not _hdrs
        if dep == "kernel_helper_functions":
            bazel_deps.append(f"//ttnn/cpp/ttnn/operations/{dep}:{dep}")
        else:
            bazel_deps.append(dep_to_label(dep))

    if not bazel_deps:
        return False  # No deps to add

    # Check if extra_deps already exists
    if "extra_deps" in content:
        print(f"  SKIP {op_path}: already has extra_deps")
        return False

    # Format the deps list
    deps_str = "    extra_deps = [\n"
    for d in sorted(bazel_deps):
        deps_str += f'        "{d}",\n'
    deps_str += "    ],\n"

    # Insert before the closing paren of ttnn_operation()
    # Find the last ")" that closes ttnn_operation
    content = content.rstrip()
    if content.endswith(")"):
        content = content[:-1] + deps_str + ")\n"
    else:
        print(f"  ERROR {op_path}: unexpected BUILD.bazel format", file=sys.stderr)
        return False

    build_file.write_text(content)
    return True


def main():
    updated = 0
    for op_path, deps in sorted(DEPENDENCIES.items()):
        if op_path in MANUAL_OPS:
            continue
        if not deps:
            continue
        if update_build_file(op_path, deps):
            print(f"  {op_path}: added {len(deps)} deps")
            updated += 1

    print(f"\nUpdated {updated} BUILD.bazel files with cross-operation deps")


if __name__ == "__main__":
    main()
