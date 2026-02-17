"""Rules for generating CMake package config files in Bazel.

Replaces CMake's configure_package_config_file() and
write_basic_package_version_file() for SDK .deb packages. The generated
files are consumed by find_package() in downstream CMake projects.

Source of truth: cmake/packaging.cmake, cmake/packaging.d/*.cmake.in
"""

def _cmake_package_config_impl(ctx):
    """Expand a CMake .in template, replacing @PACKAGE_INIT@ and @PROJECT_NAME@.

    The @PACKAGE_INIT@ macro (always on line 1) is replaced with CMake's
    standard expansion for configure_package_config_file(). The install
    destination depth (usr/lib/cmake/<pkg> = 3 levels below prefix) determines
    the ../../.. relative path in the PACKAGE_PREFIX_DIR computation.
    """
    output = ctx.actions.declare_file(ctx.attr.output_name)
    template = ctx.file.template
    project_name = ctx.attr.project_name
    input_name = template.basename

    ctx.actions.run_shell(
        outputs = [output],
        inputs = [template],
        command = """\
cat > "{output}" << 'INIT_EOF'

####### Expanded from @PACKAGE_INIT@ by configure_package_config_file() #######
####### Any changes to this file will be overwritten by the next CMake run ####
####### The input file was {input_name}                            ########

get_filename_component(PACKAGE_PREFIX_DIR "${{CMAKE_CURRENT_LIST_DIR}}/../../../" ABSOLUTE)

macro(set_and_check _var _file)
  set(${{_var}} "${{_file}}")
  if(NOT EXISTS "${{_file}}")
    message(FATAL_ERROR "File or directory ${{_file}} referenced by variable ${{_var}} does not exist !")
  endif()
endmacro()

macro(check_required_components _NAME)
  foreach(comp ${{${{_NAME}}_FIND_COMPONENTS}})
    if(NOT ${{_NAME}}_${{comp}}_FOUND)
      if(${{_NAME}}_FIND_REQUIRED_${{comp}})
        set(${{_NAME}}_FOUND FALSE)
      endif()
    endif()
  endforeach()
endmacro()

####################################################################################
INIT_EOF
# Append the rest of the template (skip line 1 which is @PACKAGE_INIT@),
# substituting @PROJECT_NAME@ with the actual project name.
tail -n +2 "{template}" | sed 's/@PROJECT_NAME@/{project_name}/g' >> "{output}"
""".format(
            output = output.path,
            template = template.path,
            input_name = input_name,
            project_name = project_name,
        ),
    )

    return [DefaultInfo(files = depset([output]))]

cmake_package_config = rule(
    implementation = _cmake_package_config_impl,
    attrs = {
        "template": attr.label(
            mandatory = True,
            allow_single_file = [".in"],
            doc = "The .cmake.in template file (from cmake/packaging.d/).",
        ),
        "project_name": attr.string(
            mandatory = True,
            doc = "CMake project name substituted for @PROJECT_NAME@ (e.g., 'Metalium').",
        ),
        "output_name": attr.string(
            mandatory = True,
            doc = "Output filename (e.g., 'tt-metalium-config.cmake').",
        ),
    },
    doc = "Expands a CMake package config template, replacing @PACKAGE_INIT@ and @PROJECT_NAME@.",
)

def _cmake_package_version_impl(ctx):
    """Generate a CMake package version file with SameMajorVersion compatibility.

    Replicates write_basic_package_version_file(COMPATIBILITY SameMajorVersion)
    from CMake 3.x. The version is read from the stamp_version output file.
    """
    output = ctx.actions.declare_file(ctx.attr.output_name)
    version_file = ctx.file.version

    ctx.actions.run_shell(
        outputs = [output],
        inputs = [version_file],
        command = """\
# Read version; extract only the numeric part (major.minor.patch).
# The stamp version may be PEP 440 (e.g., "0.65.2.dev1521") or
# a fallback ("0.0.0~dev0"). We want just the "X.Y.Z" prefix for
# CMake version comparison semantics.
RAW=$(cat "{version_file}")
VERSION=$(echo "$RAW" | grep -oE '^[0-9]+\\.[0-9]+\\.[0-9]+')
if [ -z "$VERSION" ]; then
    VERSION="0.0.0"
fi

cat > "{output}" << 'TEMPLATE_EOF'
# This is a basic version file for the Config-mode of find_package().
# It is used by write_basic_package_version_file() as input file for configure_file()
# to create a version-file which can be installed along a config.cmake file.
#
# The created file sets PACKAGE_VERSION_EXACT if the current version string and
# the requested version string are exactly the same and it sets
# PACKAGE_VERSION_COMPATIBLE if the current version is >= requested version,
# but only if the requested major version is the same as the current one.
# The variable CVF_VERSION must be set before calling configure_file().


set(PACKAGE_VERSION "@VERSION@")

if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()

  if("@VERSION@" MATCHES "^([0-9]+)\\\\.")
    set(CVF_VERSION_MAJOR "${{CMAKE_MATCH_1}}")
    if(NOT CVF_VERSION_MAJOR VERSION_EQUAL 0)
      string(REGEX REPLACE "^0+" "" CVF_VERSION_MAJOR "${{CVF_VERSION_MAJOR}}")
    endif()
  else()
    set(CVF_VERSION_MAJOR "@VERSION@")
  endif()

  if(PACKAGE_FIND_VERSION_RANGE)
    # both endpoints of the range must have the expected major version
    math (EXPR CVF_VERSION_MAJOR_NEXT "${{CVF_VERSION_MAJOR}} + 1")
    if (NOT PACKAGE_FIND_VERSION_MIN_MAJOR STREQUAL CVF_VERSION_MAJOR
        OR ((PACKAGE_FIND_VERSION_RANGE_MAX STREQUAL "INCLUDE" AND NOT PACKAGE_FIND_VERSION_MAX_MAJOR STREQUAL CVF_VERSION_MAJOR)
          OR (PACKAGE_FIND_VERSION_RANGE_MAX STREQUAL "EXCLUDE" AND NOT PACKAGE_FIND_VERSION_MAX VERSION_LESS_EQUAL CVF_VERSION_MAJOR_NEXT)))
      set(PACKAGE_VERSION_COMPATIBLE FALSE)
    elseif(PACKAGE_FIND_VERSION_MIN_MAJOR STREQUAL CVF_VERSION_MAJOR
        AND ((PACKAGE_FIND_VERSION_RANGE_MAX STREQUAL "INCLUDE" AND PACKAGE_VERSION VERSION_LESS_EQUAL PACKAGE_FIND_VERSION_MAX)
        OR (PACKAGE_FIND_VERSION_RANGE_MAX STREQUAL "EXCLUDE" AND PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION_MAX)))
      set(PACKAGE_VERSION_COMPATIBLE TRUE)
    else()
      set(PACKAGE_VERSION_COMPATIBLE FALSE)
    endif()
  else()
    if(PACKAGE_FIND_VERSION_MAJOR STREQUAL CVF_VERSION_MAJOR)
      set(PACKAGE_VERSION_COMPATIBLE TRUE)
    else()
      set(PACKAGE_VERSION_COMPATIBLE FALSE)
    endif()

    if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
      set(PACKAGE_VERSION_EXACT TRUE)
    endif()
  endif()
endif()


# if the installed or the using project don't have CMAKE_SIZEOF_VOID_P set, ignore it:
if("${{CMAKE_SIZEOF_VOID_P}}" STREQUAL "" OR "8" STREQUAL "")
  return()
endif()

# check that the installed version has the same 32/64bit-ness as the one which is currently searching:
if(NOT CMAKE_SIZEOF_VOID_P STREQUAL "8")
  math(EXPR installedBits "8 * 8")
  set(PACKAGE_VERSION "${{PACKAGE_VERSION}} (${{installedBits}}bit)")
  set(PACKAGE_VERSION_UNSUITABLE TRUE)
endif()
TEMPLATE_EOF

# Replace @VERSION@ placeholder with actual version
sed -i "s/@VERSION@/$VERSION/g" "{output}"
""".format(
            version_file = version_file.path,
            output = output.path,
        ),
    )

    return [DefaultInfo(files = depset([output]))]

cmake_package_version = rule(
    implementation = _cmake_package_version_impl,
    attrs = {
        "version": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Label of a file containing the version string (from stamp_version).",
        ),
        "output_name": attr.string(
            mandatory = True,
            doc = "Output filename (e.g., 'tt-metalium-config-version.cmake').",
        ),
    },
    doc = "Generates a CMake package version file with SameMajorVersion compatibility.",
)
