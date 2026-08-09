find_program(USBTRAIL_CLANG_EXECUTABLE NAMES clang REQUIRED)
find_program(USBTRAIL_BPFTOOL_EXECUTABLE NAMES bpftool REQUIRED)

function(usbtrail_add_bpf)
    set(options)
    set(oneValueArgs TARGET SOURCE)
    cmake_parse_arguments(BPF "${options}" "${oneValueArgs}" "" ${ARGN})

    if(NOT BPF_TARGET OR NOT BPF_SOURCE)
        message(FATAL_ERROR "usbtrail_add_bpf requires TARGET and SOURCE")
    endif()

    set(HOST_VMLINUX_BTF "/sys/kernel/btf/vmlinux")

    if(NOT EXISTS "${HOST_VMLINUX_BTF}")
        message(FATAL_ERROR
            "USBTRAIL_BUILD_BPF=ON requires ${HOST_VMLINUX_BTF}. "
            "Mount /sys/kernel/btf into Docker."
        )
    endif()

    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
        set(BPF_TARGET_ARCH "x86")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
        set(BPF_TARGET_ARCH "arm64")
    else()
        message(FATAL_ERROR "Unsupported BPF architecture: ${CMAKE_SYSTEM_PROCESSOR}")
    endif()

    set(GEN_DIR "${CMAKE_BINARY_DIR}/generated/bpf")
    set(VMLINUX_H "${GEN_DIR}/vmlinux.h")
    set(BPF_OBJ "${GEN_DIR}/${BPF_TARGET}.bpf.o")
    set(BPF_SKEL "${GEN_DIR}/${BPF_TARGET}.skel.h")

    add_custom_command(
        OUTPUT "${VMLINUX_H}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${GEN_DIR}"
        COMMAND
            "${PROJECT_SOURCE_DIR}/scripts/generate-vmlinux.sh"
            "${USBTRAIL_BPFTOOL_EXECUTABLE}"
            "${VMLINUX_H}"
        DEPENDS
            "${HOST_VMLINUX_BTF}"
            "${PROJECT_SOURCE_DIR}/scripts/generate-vmlinux.sh"
        COMMENT "Generating vmlinux.h from host kernel BTF"
        VERBATIM
    )

    set(BPF_ARCH_INCLUDE_DIR "")
    if(CMAKE_LIBRARY_ARCHITECTURE)
        set(BPF_ARCH_INCLUDE_DIR "/usr/include/${CMAKE_LIBRARY_ARCHITECTURE}")
    endif()

    set(BPF_COMPILE_COMMAND
        "${USBTRAIL_CLANG_EXECUTABLE}"
        -g
        -O2
        -target
        bpf
        "-D__TARGET_ARCH_${BPF_TARGET_ARCH}"
        -I
        "${GEN_DIR}"
        -I
        "/usr/include"
    )

    if(BPF_ARCH_INCLUDE_DIR)
        list(APPEND BPF_COMPILE_COMMAND
            -I
            "${BPF_ARCH_INCLUDE_DIR}"
        )
    endif()

    list(APPEND BPF_COMPILE_COMMAND
        -c
        "${BPF_SOURCE}"
        -o
        "${BPF_OBJ}"
    )

    add_custom_command(
        OUTPUT "${BPF_OBJ}"
        COMMAND ${BPF_COMPILE_COMMAND}
        DEPENDS
            "${BPF_SOURCE}"
            "${VMLINUX_H}"
        COMMENT "Compiling ${BPF_TARGET}.bpf.o"
        COMMAND_EXPAND_LISTS
        VERBATIM
    )

    add_custom_command(
        OUTPUT "${BPF_SKEL}"
        COMMAND
            "${PROJECT_SOURCE_DIR}/scripts/generate-skeleton.sh"
            "${USBTRAIL_BPFTOOL_EXECUTABLE}"
            "${BPF_OBJ}"
            "${BPF_SKEL}"
        DEPENDS
            "${BPF_OBJ}"
            "${PROJECT_SOURCE_DIR}/scripts/generate-skeleton.sh"
        COMMENT "Generating ${BPF_TARGET}.skel.h"
        VERBATIM
    )

    add_custom_target(${BPF_TARGET} ALL
        DEPENDS
            "${BPF_OBJ}"
            "${BPF_SKEL}"
    )
endfunction()
