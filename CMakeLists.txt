cmake_minimum_required(VERSION 3.25)

project(
    usbtrail
    VERSION 0.1.0
    DESCRIPTION "Process-oriented USB tracer for Linux"
    LANGUAGES C CXX
)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(USBTRAIL_BUILD_BPF "Build the eBPF/CO-RE object and skeleton" ON)

add_executable(usbtrail src/main.cpp)
target_include_directories(usbtrail PRIVATE "${PROJECT_SOURCE_DIR}/include")
target_compile_options(usbtrail PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang>:-Wall;-Wextra;-Wpedantic;-Wconversion;-Wshadow>
)

if(USBTRAIL_BUILD_BPF)
    include(cmake/Bpf.cmake)
    usbtrail_add_bpf(
        TARGET usbtrail_bpf
        SOURCE "${PROJECT_SOURCE_DIR}/bpf/usbtrail.bpf.c"
    )
endif()

include(CTest)
if(BUILD_TESTING)
    add_executable(usbtrail_smoke_test tests/cpp/smoke_test.cpp)
    target_compile_features(usbtrail_smoke_test PRIVATE cxx_std_20)
    add_test(NAME usbtrail.smoke COMMAND usbtrail_smoke_test)
endif()


add_custom_target(
    format
    COMMAND "${PROJECT_SOURCE_DIR}/scripts/format.sh"
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    COMMENT "Formatting USBTrail sources"
)

add_custom_target(
    format-check
    COMMAND "${PROJECT_SOURCE_DIR}/scripts/format-check.sh"
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    COMMENT "Checking USBTrail source formatting"
)

add_custom_target(
    lint
    COMMAND "${PROJECT_SOURCE_DIR}/scripts/lint.sh"
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    COMMENT "Linting USBTrail sources"
)