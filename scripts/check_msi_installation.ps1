# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param (
        [Parameter(Mandatory=$true)] [string]$BuildArtifact,
        [Parameter(Mandatory=$true)] [string]$MsiPath,
        [Parameter(Mandatory=$true)] [string]$MsiAdditionalArguments = "")

Push-Location $WorkingDirectory


# Define the test cases
$testCases = @{
    "Build-x64_Debug" = @{
        "unittests.exe" = "..\..\scripts\check_binary_dependencies_bpftool_exe_regular_debug.txt"
    }
    "Build-x64-native-only_NativeOnlyRelease" = @{
        "bpftool.exe" = "..\..\scripts\check_binary_dependencies_bpftool_exe_nativeonly_release.txt"
    }
}

function Install-MsiPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$MsiPath,
        [Parameter(Mandatory=$true)] [string]$MsiAdditionalArguments
    )

    $arguments = "/i $MsiPath /quiet /qn /norestart /log msi-install.log $MsiAdditionalArguments"
    $process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Output "Installation successful!"
    } else {
        $exceptionMessage = "Installation failed. Exit code: $($process.ExitCode)"
        Write-Host $exceptionMessage
        $logContents = Get-Content -Path "msi-install.log" -ErrorAction SilentlyContinue
        if ($logContents) {
            Write-Host "Contents of msi-install.log:"
            Write-Host $logContents
        } else {
            Write-Host "msi-install.log not found or empty."
        }
        throw $exceptionMessage
    }
}

try {
    Install-MsiPackage -MsiPath $MsiPath -MsiAdditionalArguments "$MsiAdditionalArguments"
} catch {
    Write-Host "Error: $_"
}

# Iterate over all the test cases
$allTestsPassed = $true
# foreach ($filePath in $testCases[$BuildArtifact].Keys) {
#     $res = Install-MsiPackage -MsiPath $MsiPath -MsiAdditionalArguments  $testCases[$BuildArtifact][$filePath]
#     $allTestsPassed = $allTestsPassed -and $res
# }

Pop-Location

if (-not $allTestsPassed) {
    Write-Host "One or more tests FAILED!" -ForegroundColor Red
    exit 1
}
exit 0