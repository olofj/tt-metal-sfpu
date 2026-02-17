"""Macros for building Debian packages that mirror the CMake CPack configuration.

The CMake build (cmake/packaging.cmake) produces component-based Debian packages
using CPack. Each component group becomes a separate .deb file. This module
provides a macro that wraps rules_pkg's pkg_deb to replicate that structure
with Bazel-native targets.

Source of truth: cmake/packaging.cmake, cmake/packaging.d/cpack-project-config.cmake.in
"""

load("@rules_pkg//pkg:deb.bzl", "pkg_deb")

def tt_deb(
        name,
        package,
        description,
        section,
        data_tar,
        version_file = "//packaging:deb_version",
        architecture = "amd64",
        maintainer = "Tenstorrent <support@tenstorrent.com>",
        homepage = "https://tenstorrent.com",
        depends = None,
        **kwargs):
    """Create a Debian package target mirroring CMake CPack component groups.

    Wraps pkg_deb with defaults matching the CPack configuration in
    cmake/packaging.cmake:
      - DEB-DEFAULT file naming (package_version_arch.deb)
      - Tenstorrent maintainer (CPACK_PACKAGE_CONTACT)

    Inter-package version dependencies are handled via depends_file: when
    depends entries contain "(= @VERSION@)", a genrule generates a depends
    file with the actual version substituted from the version stamp.

    Args:
        name: Target name. The .deb output is at bazel-bin/packaging/<name>.deb.
        package: Debian package name (e.g., "tt-metalium").
        description: One-line package description (CPACK_COMPONENT_*_DESCRIPTION).
        section: Debian section (e.g., "libs", "devel", "doc", "utils").
        data_tar: Label of a pkg_tar target containing the package files.
        version_file: Label of a file containing the Debian version string.
            Defaults to //packaging:deb_version (from stamp_version).
        architecture: Debian architecture (default: "amd64").
        maintainer: Package maintainer (default: Tenstorrent).
        homepage: Project homepage URL.
        depends: List of Debian package dependencies. Use "(= @VERSION@)" for
            same-version constraints (e.g., "tt-metalium (= @VERSION@)").
            The @VERSION@ placeholder is replaced with the stamped version.
        **kwargs: Forwarded to pkg_deb.
    """

    # Check if any depends entries need version substitution.
    needs_version_subst = depends and any(["@VERSION@" in d for d in depends])

    if needs_version_subst:
        # Generate a depends file with @VERSION@ replaced by the real version.
        # Each dependency on a separate line, which is what pkg_deb expects.
        deps_template = ", ".join(depends)
        depends_file_name = name + "_depends"
        native.genrule(
            name = depends_file_name,
            srcs = [version_file],
            outs = [name + "_depends.txt"],
            cmd = "echo '{}' | sed \"s/@VERSION@/$$(cat $<)/g\" > $@".format(deps_template),
        )
        pkg_deb(
            name = name,
            data = data_tar,
            package = package,
            version_file = version_file,
            architecture = architecture,
            maintainer = maintainer,
            description = description,
            section = section,
            homepage = homepage,
            depends_file = ":" + depends_file_name,
            **kwargs
        )
    else:
        pkg_deb(
            name = name,
            data = data_tar,
            package = package,
            version_file = version_file,
            architecture = architecture,
            maintainer = maintainer,
            description = description,
            section = section,
            homepage = homepage,
            depends = depends,
            **kwargs
        )
