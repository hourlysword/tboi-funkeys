# SPDX-License-Identifier: MIT
# CMake toolchain for the FunKey S: GCC 14 for arm-linux-musleabihf (built with musl-cross-make) with the FunKey SDK's
# sysroot (FunKey-OS 2.3.0: musl 1.2.1, the console's libraries, and a static SDL2 built into it), and correct maths
# functions linked into every program (FUNKEY_LIBM). scripts/build.sh passes the three paths. Libraries come from the
# sysroot only.
#
# Adapted from my other FunKey S projects.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

if(NOT FUNKEY_SDK AND DEFINED ENV{TFK_FUNKEY_SDK})
    set(FUNKEY_SDK "$ENV{TFK_FUNKEY_SDK}")
endif()
if(NOT FUNKEY_GCC AND DEFINED ENV{TFK_FUNKEY_GCC})
    set(FUNKEY_GCC "$ENV{TFK_FUNKEY_GCC}")
endif()
if(NOT FUNKEY_LIBM AND DEFINED ENV{TFK_FUNKEY_LIBM})
    set(FUNKEY_LIBM "$ENV{TFK_FUNKEY_LIBM}")
endif()
if(NOT FUNKEY_SDK OR NOT FUNKEY_GCC OR NOT FUNKEY_LIBM)
    message(FATAL_ERROR "funkey.cmake needs FUNKEY_SDK, FUNKEY_GCC and FUNKEY_LIBM (scripts/build.sh passes them)")
endif()
if(NOT EXISTS "${FUNKEY_LIBM}")
    message(FATAL_ERROR "no ${FUNKEY_LIBM}: scripts/funkey/build-libm.sh")
endif()
# Try-compile projects run the toolchain file again without the cache: pass the paths on.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES FUNKEY_SDK FUNKEY_GCC FUNKEY_LIBM)

set(CMAKE_SYSROOT "${FUNKEY_SDK}/arm-funkey-linux-musleabihf/sysroot")
set(CMAKE_C_COMPILER "${FUNKEY_GCC}/bin/arm-linux-musleabihf-gcc")
set(CMAKE_CXX_COMPILER "${FUNKEY_GCC}/bin/arm-linux-musleabihf-g++")
set(CMAKE_ASM_COMPILER "${FUNKEY_GCC}/bin/arm-linux-musleabihf-gcc")

# Allwinner V3s: one Cortex-A7 core with NEON, VFPv4 (doubles in hardware: every number of the game's ActionScript is
# a double) and hardware integer division (ARMv7VE). Thumb-2 (M4): the generated game code in Thumb-2 made the logic
# 13% faster (its code 29% smaller: it mostly waits on memory, the instruction cache's included), and the runtime too
# a few percent more with profile-guided optimisation (scripts/funkey/pgo.sh). TFK_ARM_MODE=-marm in the environment
# when a build folder is first configured: ARM mode (the flags stay in the folder's cache).
# No -ffast-math, ever: upstream builds with -ffp-contract=off so the game's physics match Flash bit for bit, and GCC
# only vectorizes floating point with NEON (which isn't IEEE-exact) under -funsafe-math-optimizations.
if(DEFINED ENV{TFK_ARM_MODE})
  set(TFK_ARM_MODE "$ENV{TFK_ARM_MODE}")
else()
  set(TFK_ARM_MODE "-mthumb")
endif()
set(TFK_ARM_FLAGS "-march=armv7ve -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard ${TFK_ARM_MODE}")
# funkey-include: headers that replace the SDK's where they don't match the console (linux/input.h: the size of an
# input event, found in my other FunKey S projects).
set(TFK_INCLUDE_FLAGS "-isystem ${CMAKE_CURRENT_LIST_DIR}/funkey-include")
# Every function and variable in its own section, so that the linker drops what nothing uses: code is file-backed, but
# under memory pressure the kernel has less of it to keep or read back.
set(CMAKE_C_FLAGS_INIT "${TFK_ARM_FLAGS} ${TFK_INCLUDE_FLAGS} -ffunction-sections -fdata-sections")
set(CMAKE_CXX_FLAGS_INIT "${TFK_ARM_FLAGS} ${TFK_INCLUDE_FLAGS} -ffunction-sections -fdata-sections")
set(CMAKE_ASM_FLAGS_INIT "${TFK_ARM_FLAGS}")

# Everything but the C library is linked statically, the C++ runtime included: FunKey-OS firmwares differ in the
# libraries they ship, and a missing one stops a program before it can log anything; GCC 14's C++ runtime is newer than
# the console's (GCC 10's). --as-needed drops libraries linked by name but unused. stack-size: musl gives threads 128 KB
# of stack unless the program asks for more; the game's generated code recurses (upstream gives its logic thread 16 MB
# on the Switch, the PSP's single thread has 1 MB). FUNKEY_LIBM: the whole archive, so that calls from the C++ runtime
# and libgcc, which come later in the link, use the correct maths too; --exclude-libs keeps them out of the exported
# symbols. scripts/funkey/check-elf.sh checks that none is left to the C library.
get_filename_component(TFK_LIBM_NAME "${FUNKEY_LIBM}" NAME)
set(TFK_LIBM_FLAGS "-Wl,--whole-archive ${FUNKEY_LIBM} -Wl,--no-whole-archive -Wl,--exclude-libs,${TFK_LIBM_NAME}")
set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-static-libstdc++ -static-libgcc -Wl,--gc-sections -Wl,--as-needed -Wl,-z,stack-size=4194304 ${TFK_LIBM_FLAGS}")
set(CMAKE_PROJECT_INCLUDE "${CMAKE_CURRENT_LIST_DIR}/funkey-static.cmake")

set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# The SDK's pkg-config wrapper looks in the sysroot (and prefixes paths with it).
set(PKG_CONFIG_EXECUTABLE "${FUNKEY_SDK}/bin/pkg-config" CACHE FILEPATH "pkg-config for the FunKey")

# Run target binaries (try_run, tests) through qemu, with the SDK's musl loader and libraries.
set(CMAKE_CROSSCOMPILING_EMULATOR qemu-arm -cpu cortex-a7 -L "${CMAKE_SYSROOT}")
