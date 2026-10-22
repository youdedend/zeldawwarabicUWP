# SPDX-License-Identifier: MPL-2.0
# Copies a staged content mod into the package's BundledMods directory (used by
# platforms/uwp-game/CMakeLists.txt for the Arabic Hesham translation).
# cmake -DSOURCE=<staged mod dir> -DOUT=<package BundledMods target> -P CopyMod.cmake
if(NOT EXISTS "${SOURCE}/manifest.json")
 message(FATAL_ERROR "CopyMod: ${SOURCE} has no manifest.json")
endif()
file(REMOVE_RECURSE "${OUT}")
file(COPY "${SOURCE}/" DESTINATION "${OUT}")
file(READ "${OUT}/manifest.json" manifest)
if(NOT manifest MATCHES "\"id\"[ \t\r\n]*:[ \t\r\n]*\"([^\"]+)\"")
 message(FATAL_ERROR "CopyMod: ${SOURCE}/manifest.json has no id")
endif()
get_filename_component(folder "${OUT}" NAME)
if(NOT CMAKE_MATCH_1 STREQUAL folder)
 message(FATAL_ERROR "CopyMod: manifest id ${CMAKE_MATCH_1} does not match the folder name ${folder}")
endif()
message(STATUS "CopyMod: ${id} -> ${OUT}")
