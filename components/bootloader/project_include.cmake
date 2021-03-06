# Do not generate flash file when building bootloader or is in early expansion of the build
if(BOOTLOADER_BUILD)
    return()
endif()

idf_build_get_property(project_dir PROJECT_DIR)

# This is for tracking the top level project path
if(BOOTLOADER_BUILD)
    set(main_project_path "${CMAKE_BINARY_DIR}/../..")
else()
    set(main_project_path "${project_dir}")
endif()

get_filename_component(secure_boot_signing_key
    "${CONFIG_SECURE_BOOT_SIGNING_KEY}"
    ABSOLUTE BASE_DIR "${main_project_path}")
if(NOT EXISTS ${secure_boot_signing_key})
    # If the signing key is not found, create a phony gen_secure_boot_signing_key target that
    # fails the build. fail_at_build_time also touches CMakeCache.txt to cause a cmake run next time
    # (to pick up a new signing key if one exists, etc.)
    fail_at_build_time(gen_secure_boot_signing_key
        "Secure Boot Signing Key ${CONFIG_SECURE_BOOT_SIGNING_KEY} does not exist. Generate using:"
        "\tespsecure.py generate_signing_key ${CONFIG_SECURE_BOOT_SIGNING_KEY}")
else()
    add_custom_target(gen_secure_boot_signing_key)
endif()


# Glue to build the bootloader subproject binary as an external
# cmake project under this one
#
#
idf_build_get_property(build_dir BUILD_DIR)
set(BOOTLOADER_BUILD_DIR "${build_dir}/bootloader")
set(bootloader_binary_files
    "${BOOTLOADER_BUILD_DIR}/bootloader.elf"
    "${BOOTLOADER_BUILD_DIR}/bootloader.bin"
    "${BOOTLOADER_BUILD_DIR}/bootloader.map"
    )

# These additional files may get generated
if(CONFIG_SECURE_BOOTLOADER_REFLASHABLE)
    set(bootloader_binary_files
        ${bootloader_binary_files}
        "${BOOTLOADER_BUILD_DIR}/bootloader-reflash-digest.bin"
        "${BOOTLOADER_BUILD_DIR}/secure-bootloader-key-192.bin"
        "${BOOTLOADER_BUILD_DIR}/secure-bootloader-key-256.bin"
        )
endif()

if((NOT CONFIG_SECURE_BOOT_ENABLED) OR
    CONFIG_SECURE_BOOTLOADER_REFLASHABLE OR
    CONFIG_SECURE_BOOTLOADER_ONE_TIME_FLASH)
    idf_build_get_property(idf_path IDF_PATH)
    idf_build_get_property(sdkconfig SDKCONFIG)
    idf_build_get_property(idf_target IDF_TARGET)
    externalproject_add(bootloader
        # TODO: support overriding the bootloader in COMPONENT_PATHS
        SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/subproject"
        BINARY_DIR "${BOOTLOADER_BUILD_DIR}"
        CMAKE_ARGS  -DSDKCONFIG=${sdkconfig} -DIDF_PATH=${idf_path} -DIDF_TARGET=${idf_target}
                    -DSECURE_BOOT_SIGNING_KEY=${secure_boot_signing_key}
                    -DPYTHON_DEPS_CHECKED=1
                    -DEXTRA_COMPONENT_DIRS=${CMAKE_CURRENT_LIST_DIR}
        INSTALL_COMMAND ""
        BUILD_ALWAYS 1  # no easy way around this...
        BUILD_BYPRODUCTS ${bootloader_binary_files}
        DEPENDS gen_secure_boot_signing_key
        )
else()
    fail_at_build_time(bootloader "Invalid bootloader target: bad sdkconfig?")
endif()

# this is a hack due to an (annoying) shortcoming in cmake, it can't
# extend the 'clean' target to the external project
# see thread: https://cmake.org/pipermail/cmake/2016-December/064660.html
#
# So for now we just have the top-level build remove the final build products...
set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY
    ADDITIONAL_MAKE_CLEAN_FILES
    ${bootloader_binary_files})