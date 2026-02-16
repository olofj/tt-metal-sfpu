#!/usr/bin/env python3
"""Add cross-operation extra_hdrs_deps to BUILD.bazel files.

Scans .hpp/.h files for #include directives that reference other operations,
then updates each operation's BUILD.bazel to include extra_hdrs_deps on the
_hdrs targets. This is needed because _hdrs targets are dependency-free by
design (to avoid cycles with ttnn_core), but when an operation's HEADERS
include headers from another operation, the _hdrs target needs those deps
so transitive users can resolve the includes.
"""

import re
import sys
from pathlib import Path

OPS_ROOT = Path("ttnn/cpp/ttnn/operations")

# Operations that don't have their own Bazel package (served by ttnn_core)
NON_PACKAGE_OPS = {"copy"}

# Operations with manually written BUILD.bazel
MANUAL_OPS = {"core", "kernel_helper_functions"}

# Known operation directories (those with BUILD.bazel)
KNOWN_OPS = set()


def find_known_ops():
    """Find all operation directories that have a BUILD.bazel."""
    for build_file in OPS_ROOT.rglob("BUILD.bazel"):
        op_dir = build_file.parent
        op_rel = str(op_dir.relative_to(OPS_ROOT))
        KNOWN_OPS.add(op_rel)


def get_op_for_file(filepath: Path) -> str | None:
    """Find the operation that a file belongs to (nearest BUILD.bazel ancestor)."""
    d = filepath.parent
    while d != OPS_ROOT and d != Path("."):
        if (d / "BUILD.bazel").exists():
            return str(d.relative_to(OPS_ROOT))
        d = d.parent
    return None


def extract_target_op(include_path: str) -> str | None:
    """Extract the target operation from an include path like ttnn/operations/X/Y/..."""
    # Remove the ttnn/operations/ prefix
    m = re.match(r'ttnn/operations/(.+)', include_path)
    if not m:
        return None
    rest = m.group(1)

    # Try to find the longest matching known operation
    parts = rest.split("/")
    for length in range(len(parts) - 1, 0, -1):
        candidate = "/".join(parts[:length])
        if candidate in KNOWN_OPS:
            return candidate

    # Also check if it's a top-level file (like math.hpp, functions.hpp, creation.hpp)
    # These are in the operations dir itself, not in a sub-operation → served by ttnn_core
    return None


def scan_header_deps() -> dict[str, set[str]]:
    """Scan all .hpp/.h files to find cross-operation header dependencies."""
    deps: dict[str, set[str]] = {}

    for ext in ("*.hpp", "*.h"):
        for header_file in OPS_ROOT.rglob(ext):
            source_op = get_op_for_file(header_file)
            if source_op is None:
                continue

            with open(header_file) as f:
                for line in f:
                    m = re.search(r'#include\s*[<"](?:ttnn/operations/(.+?))[>"]', line)
                    if not m:
                        continue
                    include_path = "ttnn/operations/" + m.group(1)
                    target_op = extract_target_op(include_path)
                    if target_op is None:
                        continue
                    if target_op == source_op:
                        continue  # Self-include
                    if target_op in NON_PACKAGE_OPS:
                        continue

                    deps.setdefault(source_op, set()).add(target_op)

    return deps


def dep_to_label(dep_op: str) -> str:
    """Convert an operation path to a Bazel _hdrs label."""
    target_name = Path(dep_op).name
    return f"//ttnn/cpp/ttnn/operations/{dep_op}:{target_name}_hdrs"


def update_build_file(op_path: str, hdrs_deps: list[str]):
    """Update a BUILD.bazel file to include extra_hdrs_deps."""
    build_file = OPS_ROOT / op_path / "BUILD.bazel"
    if not build_file.exists():
        print(f"  SKIP {op_path}: no BUILD.bazel", file=sys.stderr)
        return False

    content = build_file.read_text()

    # Filter and convert to labels
    bazel_deps = []
    for dep in sorted(hdrs_deps):
        if dep == "kernel_helper_functions":
            bazel_deps.append(f"//ttnn/cpp/ttnn/operations/{dep}:{dep}")
        else:
            bazel_deps.append(dep_to_label(dep))

    if not bazel_deps:
        return False

    # Check if extra_hdrs_deps already exists
    if "extra_hdrs_deps" in content:
        print(f"  SKIP {op_path}: already has extra_hdrs_deps")
        return False

    # Format the deps list
    deps_str = "    extra_hdrs_deps = [\n"
    for d in sorted(bazel_deps):
        deps_str += f'        "{d}",\n'
    deps_str += "    ],\n"

    # Insert after the hdrs line or after name line in ttnn_operation()
    # We need to insert extra_hdrs_deps before extra_deps or closing paren
    # Strategy: insert before "extra_deps" if it exists, else before closing ")"

    if "extra_deps" in content:
        # Insert before extra_deps
        content = content.replace("    extra_deps = [", deps_str + "    extra_deps = [")
    else:
        # Insert before closing paren
        content = content.rstrip()
        if content.endswith(")"):
            content = content[:-1] + deps_str + ")\n"
        else:
            print(f"  ERROR {op_path}: unexpected BUILD.bazel format", file=sys.stderr)
            return False

    build_file.write_text(content)
    return True


def main():
    find_known_ops()
    print(f"Found {len(KNOWN_OPS)} operation packages")

    hdrs_deps = scan_header_deps()
    print(f"Found header-level deps for {len(hdrs_deps)} operations")

    updated = 0
    for op_path, deps in sorted(hdrs_deps.items()):
        if op_path in MANUAL_OPS:
            continue
        dep_list = sorted(deps)
        if update_build_file(op_path, dep_list):
            print(f"  {op_path}: added {len(dep_list)} hdrs deps: {dep_list}")
            updated += 1

    print(f"\nUpdated {updated} BUILD.bazel files with extra_hdrs_deps")


if __name__ == "__main__":
    main()
