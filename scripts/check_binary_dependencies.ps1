# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param ([parameter(Mandatory=$false)][string] $BuildType = "regular",
       [parameter(Mandatory=$false)][string] $BuildConfiguration = "Debug",
       [Parameter(Mandatory=$True)] [string] $LogFileName)


Push-Location $WorkingDirectory
Import-Module .\common.psm1 -Force -ArgumentList ($LogFileName) -WarningAction SilentlyContinue
Write-Host (Get-Location).Path

function Test-CppBinaryDependencies {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$TextFilePath
    )

    # Run link.exe to extract dependencies
    $Output = & "dumpbin.exe" /dependents $FilePath | Out-String

    # Read the list of expected binaries from the text file
    $ExpectedBinaries = Get-Content $TextFilePath

    # Parse dumpbin.exe output to get the list of dependencies
    $Dependencies = $Output -split "`n" | Where-Object { $_.Trim().EndsWith(".dll") } | ForEach-Object { $_.Trim() }
    $Dependencies = $Dependencies[1..$Dependencies.Length] # Discard the first line, which always contains the dumped file itself.

    # Compare dependencies with expected binaries
    $MissingBinaries = Compare-Object -ReferenceObject $Dependencies -DifferenceObject $ExpectedBinaries -PassThru
    $ExtraBinaries = Compare-Object -ReferenceObject $ExpectedBinaries -DifferenceObject $Dependencies -PassThru

    if ($MissingBinaries -or $ExtraBinaries) {
        Write-Log "Mismatch found between dependencies in the file and the list:" -ForegroundColor Red
        Write-Log "Missing Dependencies:" -ForegroundColor Red
        Write-Log $MissingBinaries
        Write-Log "Extra Dependencies:" -ForegroundColor Red
        Write-Log $ExtraBinaries
        throw "Dependency check failed."
    } else {
        Write-Log "All dependencies match the list." -ForegroundColor Green
    }
}

if ($BuildType -eq "regular") {
    Test-CppBinaryDependencies -FilePath ".\Release\bpftool.exe" -TextFilePath "%SOURCE_ROOT%\scripts\check_binary_dependencies_bpftool_exe_regular.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath ".\Release\ebpfsvc.exe" -TextFilePath "%SOURCE_ROOT%\scripts\check_binary_dependencies_ebpfsvc_exe_regular.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath ".\Release\ebpfapi.dll" -TextFilePath "%SOURCE_ROOT%\scripts\check_binary_dependencies_ebpfapi_dll_regular.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath ".\Release\ebpfnetsh.dll" -TextFilePath "%SOURCE_ROOT%\scripts\check_binary_dependencies_ebpfnetsh_dll_regular.txt" | Out-Null
}

if ($BuildType -eq "regular_native-only") {
    Test-CppBinaryDependencies -FilePath ".\Release\bpftool.exe" -TextFilePath "%SOURCE_ROOT%\scripts\check_binary_dependencies_bpftool_exe_nativeonly.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath ".\Release\ebpfapi.dll" -TextFilePath "%SOURCE_ROOT%\scripts\check_binary_dependencies_ebpfapi_dll_nativeonly.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath ".\Release\ebpfnetsh.dll" -TextFilePath "%SOURCE_ROOT%\scripts\check_binary_dependencies_ebpfnetsh_dll_nativeonly.txt" | Out-Null
}

Pop-Location