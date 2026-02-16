#!/usr/bin/env python3
"""Generate BUILD.bazel files for TTNN operations from CMakeLists.txt.

Parses each operation's CMakeLists.txt and creates a corresponding BUILD.bazel
that uses the ttnn_operation() macro. Skips operations that already have a
BUILD.bazel file.

Handles special cases:
- kernel_helper_functions: INTERFACE library -> cc_library with only hdrs
- core: Both TT::Metalium and TTNN::Core are PUBLIC
- Operations with non-standard kernel glob patterns
- Operations with no headers (loss-like pattern)
"""

import json
import re
import sys
from pathlib import Path

OPS_ROOT = Path("ttnn/cpp/ttnn/operations")

# Operations that already have BUILD.bazel files — skip these
SKIP = {"bernoulli", "embedding", "matmul", "eltwise/binary", "core", "kernel_helper_functions"}


def extract_sections(content: str) -> dict:
    """Extract PRIVATE sources, PUBLIC api headers, and kernel glob patterns."""
    result = {
        "srcs": [],
        "hdrs": [],
        "kernel_globs": [],
        "is_interface": False,
        "both_public": False,  # core pattern: both deps PUBLIC
    }

    # Check if it's an INTERFACE library
    if "add_library(ttnn_op_" in content and "INTERFACE)" in content.split("add_library")[1].split("\n")[0]:
        result["is_interface"] = True

    # Check for PUBLIC TT::Metalium (core pattern)
    link_section = content[content.find("target_link_libraries"):] if "target_link_libraries" in content else ""
    if link_section:
        # Find the full target_link_libraries call
        paren_count = 0
        start = link_section.find("(")
        end = start
        for i, c in enumerate(link_section[start:], start):
            if c == "(":
                paren_count += 1
            elif c == ")":
                paren_count -= 1
                if paren_count == 0:
                    end = i
                    break
        link_call = link_section[start:end + 1]
        # Check if both deps are under PUBLIC
        if "PUBLIC" in link_call:
            after_public = link_call[link_call.find("PUBLIC"):]
            if "TTNN::Core" in after_public and "TT::Metalium" in after_public:
                # Make sure PRIVATE doesn't appear between them
                private_pos = after_public.find("PRIVATE")
                core_pos = after_public.find("TTNN::Core")
                metal_pos = after_public.find("TT::Metalium")
                if private_pos == -1 or (private_pos > core_pos and private_pos > metal_pos):
                    result["both_public"] = True

    # Extract kernel glob patterns
    glob_match = re.search(r'file\(\s*GLOB_RECURSE\s+kernels\s+(.*?)\)', content, re.DOTALL)
    if glob_match:
        paths = glob_match.group(1).strip().split("\n")
        for p in paths:
            p = p.strip()
            if p and not p.startswith("#"):
                result["kernel_globs"].append(p)

    # Extract target_sources block
    sources_match = re.search(r'target_sources\(\s*\S+\s+(.*?)\)\s*$', content, re.DOTALL | re.MULTILINE)
    if not sources_match:
        return result

    sources_block = sources_match.group(1)

    # Split into sections (PUBLIC/PRIVATE/INTERFACE)
    # Find PRIVATE section for srcs
    private_match = re.search(r'\bPRIVATE\b(.*?)(?:$|\bPUBLIC\b)', sources_block, re.DOTALL)
    if private_match:
        private_text = private_match.group(1)
        for line in private_text.strip().split("\n"):
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("FILE_SET") and \
               not line.startswith("TYPE") and not line.startswith("BASE_DIRS") and \
               not line.startswith("FILES") and line.endswith(".cpp"):
                # Fix double-slash typos from CMake (e.g. device//file.cpp)
                result["srcs"].append(line.replace("//", "/"))

    # For INTERFACE libraries, extract INTERFACE section files
    if result["is_interface"]:
        interface_match = re.search(r'\bINTERFACE\b(.*?)$', sources_block, re.DOTALL)
        if interface_match:
            interface_text = interface_match.group(1)
            for line in interface_text.strip().split("\n"):
                line = line.strip()
                if line and not line.startswith("#") and not line.startswith("FILE_SET") and \
                   not line.startswith("TYPE") and not line.startswith("BASE_DIRS") and \
                   not line.startswith("FILES") and not line.startswith("${") and \
                   line.endswith(".hpp"):
                    result["hdrs"].append(line)
        # Deduplicate while preserving order
        result["hdrs"] = list(dict.fromkeys(result["hdrs"]))
        return result

    # Extract PUBLIC FILE_SET api headers
    # Find the FILE_SET api section
    api_match = re.search(r'FILE_SET\s+api.*?FILES\s*(.*?)(?:FILE_SET|PRIVATE)', sources_block, re.DOTALL)
    if api_match:
        api_text = api_match.group(1)
        for line in api_text.strip().split("\n"):
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("$") and \
               (line.endswith(".hpp") or line.endswith(".h")):
                result["hdrs"].append(line)

    # Deduplicate while preserving order
    result["srcs"] = list(dict.fromkeys(result["srcs"]))
    result["hdrs"] = list(dict.fromkeys(result["hdrs"]))

    return result


def format_list(items: list, indent: str = "        ") -> str:
    """Format a list of strings as Bazel list syntax."""
    if not items:
        return "[]"
    lines = [f'{indent}"{item}",' for item in sorted(items)]
    return "[\n" + "\n".join(lines) + "\n    ]"


def generate_build_bazel(op_name: str, sections: dict) -> str:
    """Generate BUILD.bazel content for an operation."""

    # Special case: INTERFACE library (kernel_helper_functions)
    if sections["is_interface"]:
        lines = ['load("@rules_cc//cc:cc_library.bzl", "cc_library")', ""]
        lines.append("cc_library(")
        lines.append(f'    name = "{op_name}",')
        if sections["hdrs"]:
            lines.append(f'    hdrs = {format_list(sections["hdrs"])},' if len(sections["hdrs"]) > 1
                         else f'    hdrs = ["{sections["hdrs"][0]}"],')
        lines.append('    visibility = ["//ttnn:__subpackages__"],')
        lines.append(")")
        lines.append("")
        return "\n".join(lines)

    lines = ['load("//ttnn/bazel:ttnn_operation.bzl", "ttnn_operation")', ""]
    lines.append("ttnn_operation(")
    lines.append(f'    name = "{op_name}",')

    # Sources
    if sections["srcs"]:
        lines.append(f'    srcs = {format_list(sections["srcs"])},')
    else:
        lines.append("    srcs = [],")

    # Headers: glob all .hpp/.h files in the operation directory.
    # CMake's broad include paths (FixmeOpIncDirs) allow all headers to be found,
    # but Bazel requires explicit declaration. Many operations have headers not
    # listed in FILE_SET api (e.g., loss.hpp, *_nanobind.hpp, internal device
    # headers) that their .cpp files still include.
    #
    # For default-kernel-path ops, exclude device/kernels/** from hdrs to avoid
    # duplicates with the macro's default kernel_hdrs glob.
    has_custom_kernels = bool(sections["kernel_globs"]) and \
        set(sections["kernel_globs"]) != {"device/kernels/*"}

    if has_custom_kernels:
        # Custom kernel ops: hdrs gets all .hpp/.h, kernel_hdrs excludes .hpp/.h
        lines.append('    hdrs = glob(["**/*.hpp", "**/*.h"], allow_empty = True),')
    else:
        # Default kernel ops: exclude device/kernels/ from hdrs (macro handles those)
        lines.append('    hdrs = glob(')
        lines.append('        ["**/*.hpp", "**/*.h"],')
        lines.append('        exclude = ["device/kernels/**"],')
        lines.append('        allow_empty = True,')
        lines.append('    ),')

    # Kernel files: .cpp files shipped to device for JIT compilation (not host-compiled).
    # These are separate from hdrs because they include non-header files (.cpp).
    # The macro's default globs device/kernels/** which works for most ops.
    # For ops with non-standard kernel locations, provide explicit kernel_hdrs.
    if has_custom_kernels:
        glob_patterns = []
        for pattern in sections["kernel_globs"]:
            base = pattern.rstrip("*").rstrip("/")
            if "*" in base.split("/")[-1]:
                base = "/".join(base.split("/")[:-1])
            bazel_pattern = base + "/**"
            glob_patterns.append(bazel_pattern)
        lines.append("    kernel_hdrs = glob(")
        lines.append("        [")
        for p in sorted(glob_patterns):
            lines.append(f'            "{p}",')
        lines.append("        ],")
        lines.append('        exclude = ["**/*.hpp", "**/*.h"],')
        lines.append("        allow_empty = True,")
        lines.append("    ),")

    lines.append(")")
    lines.append("")
    return "\n".join(lines)


def find_operations() -> list:
    """Find all operation directories that have CMakeLists.txt."""
    ops = []
    for cmake in sorted(OPS_ROOT.rglob("CMakeLists.txt")):
        # Get relative path from OPS_ROOT
        rel = cmake.parent.relative_to(OPS_ROOT)
        rel_str = str(rel)

        # Skip if already has BUILD.bazel
        if rel_str in SKIP:
            continue

        # Skip nested CMakeLists.txt (only process top-level ops)
        # An operation is identified by being directly under OPS_ROOT or under
        # eltwise/ or experimental/
        parts = rel.parts
        if len(parts) == 1:
            ops.append((rel_str, cmake))
        elif len(parts) == 2 and parts[0] in ("eltwise", "experimental"):
            ops.append((rel_str, cmake))
        # Skip deeper nested CMakeLists.txt (e.g., moreh/moreh_adam/CMakeLists.txt)
    return ops


def main():
    ops = find_operations()
    print(f"Found {len(ops)} operations to convert (skipping {len(SKIP)} existing)")

    generated = 0
    errors = []

    for rel_path, cmake_path in ops:
        try:
            content = cmake_path.read_text()
            sections = extract_sections(content)

            # Determine target name (last component of path)
            target_name = Path(rel_path).name

            build_content = generate_build_bazel(target_name, sections)
            build_path = cmake_path.parent / "BUILD.bazel"
            build_path.write_text(build_content)
            generated += 1

            src_count = len(sections["srcs"])
            hdr_count = len(sections["hdrs"])
            extra = ""
            if sections["is_interface"]:
                extra = " [INTERFACE]"
            elif sections["both_public"]:
                extra = " [BOTH_PUBLIC]"
            elif sections["kernel_globs"] and set(sections["kernel_globs"]) != {"device/kernels/*"}:
                extra = " [CUSTOM_KERNELS]"
            print(f"  {rel_path}: {src_count} srcs, {hdr_count} hdrs{extra}")

        except Exception as e:
            errors.append((rel_path, str(e)))
            print(f"  ERROR {rel_path}: {e}", file=sys.stderr)

    print(f"\nGenerated {generated} BUILD.bazel files")
    if errors:
        print(f"Errors: {len(errors)}")
        for path, err in errors:
            print(f"  {path}: {err}")

    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
