# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param ([Parameter(Mandatory=$true)][string]$BuildArtifact)

Push-Location $WorkingDirectory
Write-Host "Working directory: $WorkingDirectory"

function Test-CppBinaryDependencies {
    param (
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$TextFilePath
    )

    Write-Host "Checking binary dependencies for [$BuildArtifact - $FilePath] against [$TextFilePath]..." -ForegroundColor Green

    # Run dumpbin.exe to extract dependencies
    & "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat"
    & "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
    $Output = & "dumpbin.exe" /dependents $FilePath | Out-String

    # Read the list of expected binaries from the text file
    $ExpectedBinaries = Get-Content $TextFilePath

    # Parse dumpbin.exe output to get the list of dependencies
    $Dependencies = $Output -split "`n" | Where-Object { $_.Trim().EndsWith(".dll") } | ForEach-Object { $_.Trim() }
    $Dependencies = $Dependencies[1..$Dependencies.Length] # Discard the first line, which always contains the dumped file itself.

    # Compare dependencies with the expected binaries
    $MissingBinaries = Compare-Object -ReferenceObject $Dependencies -DifferenceObject $ExpectedBinaries -PassThru
    $ExtraBinaries = Compare-Object -ReferenceObject $ExpectedBinaries -DifferenceObject $Dependencies -PassThru
    if ($MissingBinaries -or $ExtraBinaries) {
        Write-Host "Mismatch found between dependencies in the file and the list:" -ForegroundColor Red
        Write-Host "Missing Dependencies:" -ForegroundColor Red
        Write-Host $MissingBinaries
        Write-Host "Extra Dependencies:" -ForegroundColor Red
        Write-Host $ExtraBinaries
        throw "Dependency checks failed."
    } else {
        Write-Host "All dependencies match the expected list." -ForegroundColor Green
    }
}

if ($BuildArtifact -eq "Build-x64") {
    Test-CppBinaryDependencies -FilePath "bpftool.exe" -TextFilePath "$WorkingDirectory\..\..\scripts\check_binary_dependencies_bpftool_exe_regular.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath "ebpfapi.dll" -TextFilePath "$WorkingDirectory\..\..\scripts\check_binary_dependencies_ebpfapi_dll_regular.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath "ebpfnetsh.dll" -TextFilePath "$WorkingDirectory\..\..\scripts\check_binary_dependencies_ebpfnetsh_dll_regular.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath "ebpfsvc.exe" -TextFilePath "$WorkingDirectory\..\..\scripts\check_binary_dependencies_ebpfsvc_exe_regular.txt" | Out-Null
}

if ($BuildArtifact -eq "Build-x64-native-only") {
    Test-CppBinaryDependencies -FilePath "bpftool.exe" -TextFilePath "$WorkingDirectory\..\..\scripts\check_binary_dependencies_bpftool_exe_nativeonly.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath "ebpfapi.dll" -TextFilePath "$WorkingDirectory\..\..\scripts\check_binary_dependencies_ebpfapi_dll_nativeonly.txt" | Out-Null
    Test-CppBinaryDependencies -FilePath "ebpfnetsh.dll" -TextFilePath "$WorkingDirectory\..\..\scripts\check_binary_dependencies_ebpfnetsh_dll_nativeonly.txt" | Out-Null
}

Pop-Location