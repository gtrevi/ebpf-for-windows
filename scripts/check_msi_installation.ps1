# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param (
        [Parameter(Mandatory=$true)] [string]$BuildArtifact,
        [Parameter(Mandatory=$true)] [string]$MsiPath,
        [Parameter(Mandatory=$true)] [string]$MsiAdditionalArguments = "")

Push-Location $WorkingDirectory

$InstallPath = "$env:ProgramFiles\ebpf-for-windows";

# Define the test cases
$expectedFileLists = @{
    "Build-x64_Debug" = "..\..\scripts\check_msi_installation_msi_files_debug.txt"
    "Build-x64-native-only_NativeOnlyRelease" = "..\..\scripts\check_msi_installation_msi_files_nativeonly_release.txt"
}

function CompareFilesInDirectory {
    param(
        [string]$targetPath,
        [string]$listFilePath
    )

    # Read the list of files from the file
    $fileList = Get-Content $listFilePath

    # Get all files and subdirectories in the target directory
    $items = Get-ChildItem -Path $TargetPath -File -Recurse | Select-Object FullName

    # Initialize a boolean variable to track whether all files were found
    $allFilesFound = $true

    # Initialize an array to store the found files
    $foundFiles = @()

    # Recursively iterate through each file in the target path
    foreach ($item in $items) {
        # Check if the installed file is in the expected list
        if ($fileList -contains $item.FullName) {
            $foundFiles += $item.FullName
        } else {
            $allFilesFound = $false
        }
    }

    # Display the found files
    Write-Host "Found Files:"
    Write-Host $foundFiles

    # Display the missing files
    Write-Host "Missing Files:"
    $missingFiles = Compare-Object $fileList $foundFiles -PassThru
    Write-Host $missingFiles

    return $allFilesFound
}

function Install-MsiPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$MsiPath,
        [Parameter(Mandatory=$true)] [string]$MsiAdditionalArguments
    )

    $res = $true
    $arguments = "/i $MsiPath /qn /norestart /log msi-install.log $MsiAdditionalArguments"
    $process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "Installation successful!"
    } else {
        $res = $false
        $exceptionMessage = "Installation FAILED. Exit code: $($process.ExitCode)"
        Write-Host $exceptionMessage
        $logContents = Get-Content -Path "msi-install.log" -ErrorAction SilentlyContinue
        if ($logContents) {
            Write-Host "Contents of msi-install.log:"
            Write-Host $logContents
        } else {
            Write-Host "msi-install.log not found or empty."
        }
    }

    return $res
}

function Uninstall-MsiPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$MsiPath
    )

    $res = $true
    $process = Start-Process -FilePath msiexec.exe -ArgumentList "/x $MsiPath /qn /norestart /log msi-uninstall.log" -Wait -PassThru
    if ($process.ExitCode -eq 0) {
        Write-Host "Uninstallation successful!"
    } else {
        $res = $false
        $exceptionMessage = "Uninstallation FAILED. Exit code: $($process.ExitCode)"
        Write-Host $exceptionMessage
        $logContents = Get-Content -Path "msi-uninstall.log" -ErrorAction SilentlyContinue
        if ($logContents) {
            Write-Host "Contents of msi-uninstall.log:"
            Write-Host $logContents
        } else {
            Write-Host "msi-uninstall.log not found or empty."
        }
    }

    return $res
}

# Test the installation
$allTestsPassed = $true
try {
    $allTestsPassed = Install-MsiPackage -MsiPath $MsiPath -MsiAdditionalArguments "$MsiAdditionalArguments"
    $res =  CompareFilesInDirectory -targetPath $InstallPath -listFilePath $expectedFileLists[$BuildArtifact]
    $allTestsPassed = $allTestsPassed -and $res
    $res = Uninstall-MsiPackage -MsiPath $MsiPath
    $allTestsPassed = $allTestsPassed -and $res
} catch {
    Write-Host "Error: $_"
}

Pop-Location

if (-not $allTestsPassed) {
    Write-Host "One or more tests FAILED!" -ForegroundColor Red
    exit 1
}
exit 0