# SPDX-License-Identifier: MIT
# Included after every project() of a FunKey build (CMAKE_PROJECT_INCLUDE in funkey.cmake): CMake's platform files would
# otherwise reset the library suffixes the toolchain file sets. Only static libraries are found, so that the game needs
# nothing from the console but its C library (and libasound, which SDL2 loads at run time for sound).
#
# From my other FunKey S projects.
set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
