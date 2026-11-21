# CMake toolchain for PocketBook (InkView) applications.
#
# Required cache variables:
#   PB_FIRMWARE_ROOT  staged firmware directory (contains rootfs/ and ebrmain/),
#                     e.g. a pbemu staging dir like U710_6.11.2124
# Optional:
#   PB_ABI            "gnueabi" (soft-float) or "gnueabihf" (hard-float).
#                     Auto-detected from the firmware libc when unset.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

# Toolchain files are re-evaluated for try_compile projects; forward our vars.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES PB_FIRMWARE_ROOT PB_ABI)

if(NOT PB_FIRMWARE_ROOT AND DEFINED ENV{PB_FIRMWARE_ROOT})
    set(PB_FIRMWARE_ROOT "$ENV{PB_FIRMWARE_ROOT}")
endif()
if(NOT PB_FIRMWARE_ROOT OR NOT EXISTS "${PB_FIRMWARE_ROOT}/ebrmain/lib/libinkview.so")
    message(FATAL_ERROR
        "PB_FIRMWARE_ROOT must point to a staged firmware dir containing "
        "ebrmain/lib/libinkview.so (got: '${PB_FIRMWARE_ROOT}')")
endif()

set(PB_ROOTFS_LIB  "${PB_FIRMWARE_ROOT}/rootfs/lib")
set(PB_EBRMAIN_LIB "${PB_FIRMWARE_ROOT}/ebrmain/lib")

# Detect hard- vs soft-float from the firmware libc, like pbemu does.
if(NOT PB_ABI)
    find_program(_pb_readelf NAMES arm-linux-gnueabi-readelf readelf)
    execute_process(COMMAND ${_pb_readelf} -A "${PB_ROOTFS_LIB}/libc.so.6"
                    OUTPUT_VARIABLE _pb_attrs ERROR_QUIET)
    if(_pb_attrs MATCHES "Tag_ABI_VFP_args: VFP registers")
        set(PB_ABI gnueabihf)
    else()
        set(PB_ABI gnueabi)
    endif()
endif()

set(PB_TRIPLE "arm-linux-${PB_ABI}")
set(CMAKE_C_COMPILER   ${PB_TRIPLE}-gcc)
set(CMAKE_CXX_COMPILER ${PB_TRIPLE}-g++)
set(CMAKE_FIND_ROOT_PATH /usr/${PB_TRIPLE} "${PB_FIRMWARE_ROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# PocketBook devices are Cortex-A (ARMv7-A + NEON).
if(PB_ABI STREQUAL "gnueabihf")
    set(_pb_float "-mfloat-abi=hard")
else()
    set(_pb_float "-mfloat-abi=softfp")
endif()
set(CMAKE_C_FLAGS_INIT   "-march=armv7-a -mfpu=neon ${_pb_float} -fsigned-char")
set(CMAKE_CXX_FLAGS_INIT "-march=armv7-a -mfpu=neon ${_pb_float} -fsigned-char")

# Link against the firmware's own libraries (libinkview & friends). The
# cross-toolchain's glibc is used for libc itself, so -rpath-link lets ld
# resolve libinkview's transitive deps without pulling them into the binary.
set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-L${PB_EBRMAIN_LIB} -Wl,-rpath-link,${PB_EBRMAIN_LIB} -Wl,-rpath-link,${PB_ROOTFS_LIB} -Wl,--allow-shlib-undefined")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${CMAKE_EXE_LINKER_FLAGS_INIT}")

message(STATUS "PocketBook firmware: ${PB_FIRMWARE_ROOT} (${PB_TRIPLE})")
