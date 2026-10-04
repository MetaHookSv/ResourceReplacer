cmake_minimum_required(VERSION 3.21)
cmake_policy(SET CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
project(ResourceReplacer LANGUAGES CXX)

if(NOT WIN32 OR NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "ResourceReplacer requires Windows MSVC x86. Configure with -A Win32.")
endif()
get_property(multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(multi_config)
    set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING "Supported configurations" FORCE)
elseif(NOT CMAKE_BUILD_TYPE MATCHES "^(Debug|Release)$")
    message(FATAL_ERROR "Select Debug or Release.")
endif()

include(cmake/Dependencies.cmake)
resourcereplacer_prepare_dependencies()
include("${VC_LTL_Root}/VC-LTL helper for cmake.cmake")

# Include directories and definitions follow ResourceReplacer.vcxproj.
add_library(resourcereplacer_settings INTERFACE)
target_compile_features(resourcereplacer_settings INTERFACE cxx_std_20)
target_include_directories(resourcereplacer_settings INTERFACE
    src
    "${METAHOOK_SOURCE_PATH}/include"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/cl_dll"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/common"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/engine"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/pm_shared"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/public"
    "${METAHOOK_SOURCE_PATH}/include/SourceSDK"
    "${METAHOOK_SOURCE_PATH}/include/SourceSDK/tier0"
    "${METAHOOK_SOURCE_PATH}/include/SourceSDK/tier1"
    "${METAHOOK_SOURCE_PATH}/include/SourceSDK/tier3"
    "${METAHOOK_SOURCE_PATH}/include/SourceSDK/vstdlib"
    "${METAHOOK_SOURCE_PATH}/include/Interface"
    ${RESOURCEREPLACER_CAPSTONE_INCLUDE_DIRS}
)
target_compile_definitions(resourcereplacer_settings INTERFACE
    WIN32 _WINDOWS _USRDLL _MBCS NO_MALLOC_OVERRIDE NO_VCR
    $<$<CONFIG:Debug>:_DEBUG>
    $<$<CONFIG:Release>:NDEBUG>)
target_compile_options(resourcereplacer_settings INTERFACE /permissive
    $<$<CONFIG:Debug>:/W0>
    $<$<CONFIG:Release>:/W3>
    /wd4311 /wd4312 /wd4819 /wd4996)

include(cmake/Sources.cmake)
add_library(ResourceReplacer SHARED ${RESOURCEREPLACER_SOURCES})
target_link_libraries(ResourceReplacer PRIVATE resourcereplacer_settings)
target_compile_options(ResourceReplacer PRIVATE /MP /Zi)
target_link_options(ResourceReplacer PRIVATE /DEBUG /SUBSYSTEM:WINDOWS
    $<$<CONFIG:Debug>:/INCREMENTAL>
    $<$<CONFIG:Release>:/INCREMENTAL:NO>
    $<$<CONFIG:Release>:/OPT:REF>
    $<$<CONFIG:Release>:/OPT:ICF>)
set_target_properties(ResourceReplacer PROPERTIES INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)

install(TARGETS ResourceReplacer RUNTIME DESTINATION svencoop/metahook/plugins)
install(FILES "$<TARGET_PDB_FILE:ResourceReplacer>" DESTINATION svencoop/metahook/plugins)

option(RESOURCEREPLACER_SYNC_GAMEDATA "Download and prune ResourceReplacer's gamedata catalog before building" ON)
set(RESOURCEREPLACER_GAMEDATA_DIR "${PROJECT_BINARY_DIR}/assets/svencoop/metahook/gamedata/resourcereplacer" CACHE PATH "ResourceReplacer gamedata catalog directory")
if(RESOURCEREPLACER_SYNC_GAMEDATA)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    add_custom_target(ResourceReplacerGameData
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/sync-gamedata.py"
            --manifest "${CMAKE_CURRENT_SOURCE_DIR}/scripts/manifests/resourcereplacer.json"
            --target-dir "${RESOURCEREPLACER_GAMEDATA_DIR}" --temp-root "${PROJECT_BINARY_DIR}/gamedata-sync"
        COMMENT "Synchronizing and validating ResourceReplacer gamedata"
        VERBATIM)
    add_custom_target(ResourceReplacerGameDataValidate
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/validate-gamedata.py"
            "${RESOURCEREPLACER_GAMEDATA_DIR}" --manifest "${CMAKE_CURRENT_SOURCE_DIR}/scripts/manifests/resourcereplacer.json"
        COMMENT "Validating ResourceReplacer gamedata against the manifest"
        VERBATIM)
    add_dependencies(ResourceReplacerGameDataValidate ResourceReplacerGameData)
    add_dependencies(ResourceReplacer ResourceReplacerGameDataValidate)
endif()
install(DIRECTORY "${RESOURCEREPLACER_GAMEDATA_DIR}/" DESTINATION svencoop/metahook/gamedata/resourcereplacer OPTIONAL)
