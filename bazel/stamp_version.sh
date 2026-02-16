#!/bin/bash
# Bazel workspace status command for version stamping.
#
# Replicates the setuptools_scm "guess-next-dev" version scheme configured in
# pyproject.toml so that Bazel-built artifacts embed the same version string
# as pip-built wheels.
#
# Usage (in .bazelrc):
#   build --workspace_status_command=bazel/stamp_version.sh
#
# Output format (Bazel workspace status key-value pairs):
#   STABLE_VERSION <pep440-version>     — invalidates actions when changed
#   STABLE_GIT_COMMIT <full-sha>        — invalidates actions when changed
#   STABLE_GIT_TAG <nearest-tag>        — invalidates actions when changed
#   BUILD_TIMESTAMP <YYYYMMDDHHmmss>    — volatile, does NOT invalidate actions
#   BUILD_HOST <hostname>               — volatile, does NOT invalidate actions
set -euo pipefail

# ---------------------------------------------------------------------------
# Step 1: Run the same git describe command as pyproject.toml
#
# pyproject.toml [tool.setuptools_scm] git_describe_command:
#   git describe --dirty --tags --long
#     --match v[0-9]*.[0-9]*.[0-9]*
#     --match v[0-9]*.[0-9]*.[0-9]*-rc[0-9]*
#     --exclude *-dev*
# ---------------------------------------------------------------------------
git_describe=$(
    git describe --dirty --tags --long \
        --match 'v[0-9]*.[0-9]*.[0-9]*' \
        --match 'v[0-9]*.[0-9]*.[0-9]*-rc[0-9]*' \
        --exclude '*-dev*' 2>/dev/null
) || git_describe=""

if [[ -z "$git_describe" ]]; then
    # No matching tags reachable — use fallback (matches pyproject.toml fallback_version)
    version="0.0.0.dev0"
    nearest_tag="untagged"
else
    # --long always produces: <tag>-<distance>-g<hash>[-dirty]
    # Strip optional -dirty suffix (we track it separately)
    dirty=""
    desc="$git_describe"
    if [[ "$desc" == *-dirty ]]; then
        dirty=".d$(date -u +%Y%m%d)"
        desc="${desc%-dirty}"
    fi

    # Parse: v<tag>-<distance>-g<hash>
    # Work from the right: hash is after last '-g', distance is before that
    hash="${desc##*-g}"
    rest="${desc%-g*}"
    distance="${rest##*-}"
    tag="${rest%-*}"

    # Strip leading 'v' from tag
    tag_version="${tag#v}"
    nearest_tag="$tag"

    if [[ "$distance" -eq 0 ]]; then
        # Exact tag match — clean version
        # Normalize: v1.2.3-rc1 → 1.2.3rc1 (PEP 440)
        version="${tag_version//-rc/rc}"
    else
        # Commits after tag — apply "guess-next-dev" scheme:
        # 1. Parse base version (stripping any pre-release suffix)
        # 2. Bump the patch (last) component
        # 3. Append .dev<distance>
        #
        # Examples:
        #   v0.65.1-rc16, distance 1521 → 0.65.2.dev1521
        #   v1.2.3, distance 5         → 1.2.4.dev5

        # Strip pre-release suffix (-rc1, -alpha2, etc.) from version
        base_version="${tag_version%%-rc*}"
        base_version="${base_version%%-alpha*}"
        base_version="${base_version%%-beta*}"

        # Split into major.minor.patch
        IFS='.' read -r major minor patch <<< "$base_version"
        patch="${patch:-0}"

        # Bump patch
        next_patch=$((patch + 1))
        version="${major}.${minor}.${next_patch}.dev${distance}"
    fi
fi

# ---------------------------------------------------------------------------
# Step 2: Output Bazel workspace status key-value pairs
# ---------------------------------------------------------------------------

# STABLE_ prefix: changes to these values invalidate the action cache for
# targets that consume them (via stamp=1 on py_wheel, pkg_deb, etc.)
echo "STABLE_VERSION ${version}"
echo "STABLE_GIT_COMMIT $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo "STABLE_GIT_TAG ${nearest_tag:-untagged}"

# Volatile keys (no STABLE_ prefix): do NOT invalidate actions.
# Embedded in stamped outputs but won't trigger rebuilds.
echo "BUILD_TIMESTAMP $(date -u +%Y%m%d%H%M%S)"
echo "BUILD_HOST $(hostname)"
