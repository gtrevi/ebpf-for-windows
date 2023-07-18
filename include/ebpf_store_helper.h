// Copyright (c) Microsoft Corporation
// SPDX-License-Identifier: MIT

#pragma once

#ifndef USER_MODE
#include "framework.h"
#define __return_type NTSTATUS
#define _SUCCESS STATUS_SUCCESS
#define IS_SUCCESS(x) (NT_SUCCESS(x))
typedef HANDLE ebpf_registry_key_t;
#else
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winreg.h>
#define __return_type uint32_t
#define IS_SUCCESS(x) (x == ERROR_SUCCESS)
#define _SUCCESS NO_ERROR
typedef HKEY ebpf_registry_key_t;
extern ebpf_registry_key_t ebpf_root_registry_key;
#endif

#include "ebpf_program_types.h"
#include "ebpf_windows.h"

#define GUID_STRING_LENGTH 38 // not including the null terminator.
typedef _Return_type_success_(NT_SUCCESS(return )) uint32_t ebpf_registry_result_t;

/**
 * @brief Open the root of the eBPF registry.
 *
 * @param[in] provider_key Pointer to the registry key to be initialized.
 * @returns  Status of the operation.
 */
uint32_t
ebpf_store_open_or_create_provider_registry_key(_Out_ ebpf_registry_key_t* provider_key);

/**
 * @brief Update the provider information in the eBPF registry.
 *
 * @param helper_info_key
 * @param helper_info
 * @return __return_type
 */
__return_type
ebpf_store_update_helper_prototype(
    ebpf_registry_key_t helper_info_key, _In_ const ebpf_helper_function_prototype_t* helper_info);

/**
 * @brief Update section information in eBPF store.
 *
 * @param[in] section_info Pointer to an array of section information.
 * @param[in] section_info_count Count of section information entries.
 *
 * @returns Status of the operation.
 */
__return_type
ebpf_store_update_section_information(
    _In_reads_(section_info_count) const ebpf_program_section_info_t* section_info, uint32_t section_info_count);

/**
 * @brief Update program information in eBPF store.
 *
 * @param[in] program_info Pointer to an array of program information.
 * @param[in] program_info_count Count of program information entries.
 *
 * @returns Status of the operation.
 */
__return_type
ebpf_store_update_program_information(
    _In_reads_(program_info_count) const ebpf_program_info_t* program_info, uint32_t program_info_count);

/**
 * @brief Update global helper information in eBPF store.
 *
 * @param[in] helper_info Pointer to an array of helper function prototypes.
 * @param[in] helper_info_count Count of helper function prototypes.
 *
 * @returns Status of the operation.
 */
__return_type
ebpf_store_update_global_helper_information(
    _In_reads_(helper_info_count) ebpf_helper_function_prototype_t* helper_info, uint32_t helper_info_count);