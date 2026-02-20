#!/usr/bin/env python3
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0

"""Generate BUILD.bazel files for model test directories.

Walks models/ finding directories with test_*.py but no BUILD.bazel, then
generates pytest_suite targets following the canonical pattern used by existing
model test BUILD files.

Usage:
    python bazel/generate_model_builds.py             # dry-run (prints what would be created)
    python bazel/generate_model_builds.py --write      # actually write files
    python bazel/generate_model_builds.py --amend      # also amend stub BUILD files
"""

import argparse
import glob
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODELS_DIR = ROOT / "models"

# ---------------------------------------------------------------------------
# Skip rules
# ---------------------------------------------------------------------------

# Imports that indicate missing Bazel pip deps — defer these directories.
BLOCKING_IMPORTS = {
    "tt_lib",
    "cv2",
    "kagglehub",
}

# Path segments that indicate non-test directories (scripts, reference impls,
# utility modules) even if they contain test_*.py files.
NON_TEST_PATH_SEGMENTS = {"reference", "scripts", "utils"}

# Specific directories to skip (relative to repo root).
SKIP_DIRS = {
    # vllm test utilities — not pytest tests, they're model utility modules
    "models/vllm_test_utils/no_op_test",
    "models/vllm_test_utils/t3000_multiproc_test",
    # Relative-import packages (use unittest, not pytest)
    "models/demos/t3000/llama2_70b/reference/llama/llama",
    # Segmentation evaluation — heavy eval deps (cv2 etc.)
    "models/demos/vision/segmentation/segmentation_evaluation",
}

# Stub BUILD.bazel files that exist but need pytest_suite added.
# (Phase 1 already populated deepseek_v3 and gpt_oss stubs.)
STUB_BUILD_FILES: set[str] = set()

# ---------------------------------------------------------------------------
# Hardware tag detection from path
# ---------------------------------------------------------------------------


def hw_tags_from_path(rel_dir: str) -> list[str]:
    """Determine hardware requirement tags from directory path."""
    parts = rel_dir.split("/")
    if "blackhole" in parts:
        return ["requires_blackhole"]
    if "t3000" in parts:
        return ["requires_wormhole_b0", "requires_T3000"]
    if "tg" in parts or "galaxy" in parts:
        return ["requires_wormhole_b0", "requires_galaxy"]
    return ["requires_wormhole_b0"]


# ---------------------------------------------------------------------------
# Import scanning
# ---------------------------------------------------------------------------


def scan_imports(test_files: list[Path]) -> dict:
    """Scan test files for imports that affect deps/skip decisions.

    Returns dict with keys:
        blocking: set of blocking import names found
        torchvision: bool
        pil: bool
        tests_ttnn: bool
        tests_tt_eager: bool
    """
    result = {
        "blocking": set(),
        "torchvision": False,
        "pil": False,
        "diffusers": False,
        "datasets": False,
        "evaluate": False,
        "timm": False,
        "scipy": False,
        "tests_ttnn": False,
        "tests_tt_eager": False,
    }

    import_re = re.compile(
        r"^\s*(?:import|from)\s+([\w.]+)", re.MULTILINE
    )

    for f in test_files:
        try:
            content = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        for m in import_re.finditer(content):
            mod = m.group(1)
            top = mod.split(".")[0]

            if top in BLOCKING_IMPORTS:
                result["blocking"].add(top)
            if top == "torchvision" or mod.startswith("torchvision"):
                result["torchvision"] = True
            if top == "PIL" or mod.startswith("PIL"):
                result["pil"] = True
            if top == "diffusers":
                result["diffusers"] = True
            if top == "datasets":
                result["datasets"] = True
            if top == "evaluate":
                result["evaluate"] = True
            if top == "timm":
                result["timm"] = True
            if top == "scipy":
                result["scipy"] = True
            if mod.startswith("tests.ttnn"):
                result["tests_ttnn"] = True
            if mod.startswith("tests.tt_eager"):
                result["tests_tt_eager"] = True

    return result


# ---------------------------------------------------------------------------
# Name derivation
# ---------------------------------------------------------------------------


def suite_name_from_path(rel_dir: str) -> str:
    """Derive a test suite name from the directory path.

    Examples:
        models/demos/bert/tests -> bert_tests
        models/demos/wormhole/mamba/tests -> mamba_tests
        models/experimental/bloom/tests -> bloom_tests
        models/demos/t3000/falcon40b/tests/unit_tests -> falcon40b_unit_tests
        models/demos/vision/classification/vgg/tests -> vgg_tests
        models/demos/blackhole/sentence_bert/tests/pcc -> sentence_bert_pcc_tests
    """
    parts = rel_dir.split("/")

    # Remove common prefixes that don't add information
    skip = {"models", "demos", "experimental", "common", "vision",
            "classification", "segmentation", "generative", "audio",
            "multimodal", "wormhole", "blackhole", "t3000", "tg",
            "tt_dit", "tt_cnn", "tt_transformers"}

    meaningful = [p for p in parts if p not in skip]

    # If we stripped too much, use last 2 path components
    if not meaningful:
        meaningful = parts[-2:]

    # Common patterns: take the model name + optional suffix
    # e.g., ["bert", "tests"] -> "bert"
    # e.g., ["falcon40b", "tests", "unit_tests"] -> "falcon40b_unit_tests"
    # e.g., ["sentence_bert", "tests", "pcc"] -> "sentence_bert_pcc"
    name_parts = []
    for p in meaningful:
        if p == "tests":
            continue
        name_parts.append(p)

    if not name_parts:
        name_parts = [parts[-1]]

    name = "_".join(name_parts)
    # Sanitize: Bazel target names allow [a-zA-Z0-9_.-]
    name = re.sub(r"[^a-zA-Z0-9_]", "_", name)
    # Avoid double _tests suffix (e.g., falcon40b_unit_tests_tests)
    if name.endswith("_tests"):
        return name
    return name + "_tests"


# ---------------------------------------------------------------------------
# Comment for the file header
# ---------------------------------------------------------------------------


def header_comment(rel_dir: str) -> str:
    """Generate a descriptive header comment."""
    # Extract model name from path
    parts = rel_dir.split("/")
    # Find the most descriptive segment
    for skip in ("models", "demos", "experimental", "common", "tests"):
        if skip in parts:
            idx = parts.index(skip)
            remaining = [p for p in parts[idx + 1:] if p != "tests"]
            if remaining:
                model = remaining[0].replace("_", " ").title()
                return f"# {model} model tests."
    return f"# Model tests for {'/'.join(parts[-2:])}."


# ---------------------------------------------------------------------------
# BUILD.bazel generation
# ---------------------------------------------------------------------------


def _format_starlark_list(items: list[str]) -> str:
    """Format a Python list as a Starlark list literal with double quotes."""
    return "[" + ", ".join(f'"{item}"' for item in items) + "]"


def generate_build_content(
    rel_dir: str,
    test_files: list[Path],
    imports: dict,
) -> str:
    """Generate BUILD.bazel content for a test directory."""
    hw = hw_tags_from_path(rel_dir)
    name = suite_name_from_path(rel_dir)

    # Base deps — same as all existing model BUILD.bazel files
    deps = [
        '"//models/common:utility_functions"',
        '"//ttnn/ttnn:ttnn_py"',
        '"@pip//loguru"',
        '"@pip//torch"',
        '"@pip//transformers"',
    ]

    # Extra deps from import scanning
    if imports["torchvision"]:
        deps.append('"@pip//torchvision"')
    if imports["pil"]:
        deps.append('"@pip//pillow"')
    if imports["diffusers"]:
        deps.append('"@pip//diffusers"')
    if imports["datasets"]:
        deps.append('"@pip//datasets"')
    if imports["evaluate"]:
        deps.append('"@pip//evaluate"')
    if imports["timm"]:
        deps.append('"@pip//timm"')
    if imports["scipy"]:
        deps.append('"@pip//scipy"')
    if imports["tests_ttnn"]:
        deps.append('"//tests/ttnn:test_utils"')
    if imports["tests_tt_eager"]:
        deps.append('"//tests/tt_eager:sweep_test_utils"')

    tags = ["ttnn", "nightly", "models"] + hw

    # Check if there's a conftest.py to export
    has_conftest = (MODELS_DIR.parent / rel_dir / "conftest.py").exists()

    lines = []
    lines.append(header_comment(rel_dir))
    lines.append("")
    lines.append('load("//bazel:pytest.bzl", "pytest_suite")')
    lines.append("")

    if has_conftest:
        lines.append('exports_files(["conftest.py"])')
        lines.append("")

    lines.append("pytest_suite(")
    lines.append(f'    name = "{name}",')
    lines.append('    srcs = glob(["test_*.py"]),')
    lines.append("    deps = [")
    for d in deps:
        lines.append(f"        {d},")
    lines.append("    ],")
    lines.append('    markers = ["slow"],')
    lines.append(f"    tags = {_format_starlark_list(tags)},")
    lines.append(")")
    lines.append("")

    return "\n".join(lines)


def generate_conftest_only(rel_dir: str) -> str:
    """Generate a minimal BUILD.bazel that only exports conftest.py."""
    return f'{header_comment(rel_dir)}\n\nexports_files(["conftest.py"])\n'


def generate_stub_amendment(rel_dir: str, test_files: list[Path], imports: dict) -> str:
    """Generate pytest_suite content to append to a stub BUILD.bazel."""
    hw = hw_tags_from_path(rel_dir)
    name = suite_name_from_path(rel_dir)

    deps = [
        '"//models/common:utility_functions"',
        '"//ttnn/ttnn:ttnn_py"',
        '"@pip//loguru"',
        '"@pip//torch"',
        '"@pip//transformers"',
    ]

    if imports["torchvision"]:
        deps.append('"@pip//torchvision"')
    if imports["pil"]:
        deps.append('"@pip//pillow"')
    if imports["diffusers"]:
        deps.append('"@pip//diffusers"')
    if imports["datasets"]:
        deps.append('"@pip//datasets"')
    if imports["evaluate"]:
        deps.append('"@pip//evaluate"')
    if imports["timm"]:
        deps.append('"@pip//timm"')
    if imports["scipy"]:
        deps.append('"@pip//scipy"')
    if imports["tests_ttnn"]:
        deps.append('"//tests/ttnn:test_utils"')
    if imports["tests_tt_eager"]:
        deps.append('"//tests/tt_eager:sweep_test_utils"')

    tags = ["ttnn", "nightly", "models"] + hw

    lines = []
    lines.append("")
    lines.append('load("//bazel:pytest.bzl", "pytest_suite")')
    lines.append("")
    lines.append("pytest_suite(")
    lines.append(f'    name = "{name}",')
    lines.append('    srcs = glob(["test_*.py"]),')
    lines.append("    deps = [")
    for d in deps:
        lines.append(f"        {d},")
    lines.append("    ],")
    lines.append('    markers = ["slow"],')
    lines.append(f"    tags = {_format_starlark_list(tags)},")
    lines.append(")")
    lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def find_candidate_dirs() -> list[tuple[str, list[Path], str]]:
    """Find directories that need BUILD.bazel files.

    Returns list of (rel_dir, test_files, action) where action is one of:
        "create" — new BUILD.bazel
        "amend" — append to existing stub BUILD.bazel
        "conftest_only" — directory has conftest.py but no tests
    """
    candidates = []

    # Find all directories with test_*.py under models/
    test_dirs: dict[str, list[Path]] = {}
    for test_file in sorted(MODELS_DIR.rglob("test_*.py")):
        d = test_file.parent
        rel = str(d.relative_to(ROOT))
        test_dirs.setdefault(rel, []).append(test_file)

    for rel_dir, test_files in sorted(test_dirs.items()):
        build_path = ROOT / rel_dir / "BUILD.bazel"

        # Check if this is a stub BUILD that needs amendment
        if rel_dir in STUB_BUILD_FILES:
            candidates.append((rel_dir, test_files, "amend"))
            continue

        # Skip directories that already have BUILD.bazel
        if build_path.exists():
            continue

        # Skip explicitly excluded directories
        if rel_dir in SKIP_DIRS:
            continue

        # Skip non-test directories (reference, scripts, utils)
        parts = set(rel_dir.split("/"))
        if parts & NON_TEST_PATH_SEGMENTS:
            continue

        # Scan imports for blocking deps
        imports = scan_imports(test_files)
        if imports["blocking"]:
            continue

        candidates.append((rel_dir, test_files, "create"))

    # Find conftest-only directories (conftest.py but no tests, no BUILD.bazel)
    for conftest in sorted(MODELS_DIR.rglob("conftest.py")):
        d = conftest.parent
        rel = str(d.relative_to(ROOT))
        build_path = d / "BUILD.bazel"

        if build_path.exists():
            continue

        # Check if this dir has test files (already handled above)
        has_tests = any(d.glob("test_*.py"))
        if has_tests:
            continue

        candidates.append((rel, [], "conftest_only"))

    return candidates


def main():
    parser = argparse.ArgumentParser(description="Generate BUILD.bazel for model test dirs")
    parser.add_argument("--write", action="store_true", help="Actually write files (default: dry-run)")
    parser.add_argument("--amend", action="store_true", help="Also amend stub BUILD files")
    args = parser.parse_args()

    os.chdir(ROOT)
    candidates = find_candidate_dirs()

    created = 0
    amended = 0
    conftest_only = 0
    skipped_amend = 0

    for rel_dir, test_files, action in candidates:
        build_path = ROOT / rel_dir / "BUILD.bazel"

        if action == "conftest_only":
            content = generate_conftest_only(rel_dir)
            conftest_only += 1
            if args.write:
                build_path.write_text(content)
                print(f"  CREATED (conftest-only): {rel_dir}/BUILD.bazel")
            else:
                print(f"  [dry-run] Would create (conftest-only): {rel_dir}/BUILD.bazel")
            continue

        imports = scan_imports(test_files)

        if action == "amend":
            if not args.amend:
                skipped_amend += 1
                print(f"  SKIPPED (use --amend): {rel_dir}/BUILD.bazel")
                continue
            amendment = generate_stub_amendment(rel_dir, test_files, imports)
            amended += 1
            if args.write:
                existing = build_path.read_text()
                build_path.write_text(existing.rstrip() + "\n" + amendment)
                print(f"  AMENDED: {rel_dir}/BUILD.bazel")
            else:
                print(f"  [dry-run] Would amend: {rel_dir}/BUILD.bazel")
                print(amendment)
            continue

        # action == "create"
        content = generate_build_content(rel_dir, test_files, imports)
        created += 1
        if args.write:
            build_path.write_text(content)
            print(f"  CREATED: {rel_dir}/BUILD.bazel")
        else:
            print(f"  [dry-run] Would create: {rel_dir}/BUILD.bazel")

    print(f"\nSummary: {created} created, {amended} amended, {conftest_only} conftest-only"
          f"{f', {skipped_amend} amend-skipped (use --amend)' if skipped_amend else ''}")


if __name__ == "__main__":
    main()
