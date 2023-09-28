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

    # Run and parse the dumpbin.exe output to extract dependencies
    # & "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat"
    # & "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
    # $Output = & "dumpbin.exe" /dependents $FilePath | Out-String
    $Output = & "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\14.35.32215\bin\Hostx64\x64\dumpbin.exe" /dependents $FilePath | Out-String
    # Parse dumpbin.exe output to get the list of dependencies
    $Dependencies = $Output -split "`n" | Where-Object { $_.Trim().EndsWith(".dll") } | ForEach-Object { $_.Trim() }
    $Dependencies = $Dependencies[1..$Dependencies.Length] # Discard the first line, which always contains the dumped file itself.
    Write-Host "Dependency list for '$FilePath':" -ForegroundColor Red
    Write-Host $Dependencies

    # Read the list of expected binaries from the text file
    $ExpectedBinaries = Get-Content $TextFilePath
    Write-Host "Expected dependency list:" -ForegroundColor Red
    Write-Host $ExpectedBinaries

    # Compare dependencies with the expected binaries
    $MissingBinaries = Compare-Object -ReferenceObject $Dependencies -DifferenceObject $ExpectedBinaries -PassThru
    $ExtraBinaries = Compare-Object -ReferenceObject $ExpectedBinaries -DifferenceObject $Dependencies -PassThru
    if ($MissingBinaries -or $ExtraBinaries) {
        Write-Host "Mismatch found between dependencies in the file and the list:" -ForegroundColor Red
        Write-Host "Missing Dependencies:" -ForegroundColor Red
        Write-Host $MissingBinaries
        Write-Host "Extra Dependencies:" -ForegroundColor Red
        Write-Host $ExtraBinaries
        return $false
    } else {
        Write-Host "All dependencies match the expected list." -ForegroundColor Green
        return $true
    }
}

$allTestsPassed = $true
if ($BuildArtifact -eq "Build-x64") {
    $allTestsPassed = $allTestsPassed -and (Test-CppBinaryDependencies -FilePath "bpftool.exe" -TextFilePath "..\..\scripts\check_binary_dependencies_bpftool_exe_regular.txt")
    $allTestsPassed = $allTestsPassed -and (Test-CppBinaryDependencies -FilePath "ebpfapi.dll" -TextFilePath "..\..\scripts\check_binary_dependencies_ebpfapi_dll_regular.txt")
    $allTestsPassed = $allTestsPassed -and (Test-CppBinaryDependencies -FilePath "ebpfnetsh.dll" -TextFilePath "..\..\scripts\check_binary_dependencies_ebpfnetsh_dll_regular.txt")
    $allTestsPassed = $allTestsPassed -and (Test-CppBinaryDependencies -FilePath "ebpfsvc.exe" -TextFilePath "..\..\scripts\check_binary_dependencies_ebpfsvc_exe_regular.txt")
}
if ($BuildArtifact -eq "Build-x64-native-only") {
    $allTestsPassed = $allTestsPassed -and (Test-CppBinaryDependencies -FilePath "bpftool.exe" -TextFilePath "..\..\scripts\check_binary_dependencies_bpftool_exe_nativeonly.txt")
    $allTestsPassed = $allTestsPassed -and (Test-CppBinaryDependencies -FilePath "ebpfapi.dll" -TextFilePath "..\..\scripts\check_binary_dependencies_ebpfapi_dll_nativeonly.txt")
    $allTestsPassed = $allTestsPassed -and (Test-CppBinaryDependencies -FilePath "ebpfnetsh.dll" -TextFilePath "..\..\scripts\check_binary_dependencies_ebpfnetsh_dll_nativeonly.txt")
}

Pop-Location

if (-not $allTestsPassed) {
    Write-Host "One or more tests failed. Exiting script." -ForegroundColor Red
    exit 1
}
exit 0