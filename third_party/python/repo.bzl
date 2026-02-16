"""Repository rule to auto-detect system Python headers.

Discovers the Python include directory using the system python3 interpreter,
then creates a cc_library target that provides the headers. This mirrors
CMake's find_package(Python3 COMPONENTS Development.Module).

When rules_python is adopted later, this can be replaced with hermetic
Python toolchain headers. For now, system detection matches the CMake build.
"""

def _python_headers_impl(ctx):
    python3 = ctx.which("python3")
    if not python3:
        fail("python3 not found on PATH. Install Python 3.12+ development headers.")

    # Get the include path from sysconfig (same as CMake's Python3_INCLUDE_DIRS).
    result = ctx.execute([
        python3,
        "-c",
        "import sysconfig; print(sysconfig.get_path('include'))",
    ])
    if result.return_code != 0:
        fail("Failed to detect Python include path: " + result.stderr)
    include_dir = result.stdout.strip()

    # Get the Python version for validation.
    result = ctx.execute([
        python3,
        "-c",
        "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')",
    ])
    if result.return_code != 0:
        fail("Failed to detect Python version: " + result.stderr)
    version = result.stdout.strip()
    major, minor = version.split(".")
    if int(major) < 3 or (int(major) == 3 and int(minor) < 12):
        fail("Python >= 3.12 required for stable ABI (abi3). Found: " + version)

    # Symlink the system Python headers into the repository.
    ctx.symlink(include_dir, "include")

    # Generate BUILD.bazel exposing a cc_library.
    ctx.file("BUILD.bazel", content = """\
load("@rules_cc//cc:cc_library.bzl", "cc_library")

cc_library(
    name = "headers",
    hdrs = glob(["include/**/*.h"]),
    includes = ["include"],
    visibility = ["//visibility:public"],
)
""")

python_headers = repository_rule(
    implementation = _python_headers_impl,
    local = True,  # Re-evaluate when workspace changes (system Python upgrade).
    doc = "Auto-detect system Python headers for building C extensions.",
)
