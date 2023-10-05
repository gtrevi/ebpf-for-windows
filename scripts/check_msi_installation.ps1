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
    $items = Get-ChildItem $targetPath -Recurse

    # Initialize a boolean variable to track whether all files were found
    $allFilesFound = $true

    # Initialize an array to store the found files
    $foundFiles = @()

    # Iterate through each item (file or directory) in the target path
    foreach ($item in $items) {
        if ($item.GetType() -eq [System.IO.FileInfo]) {
            # If the item is a file, check if it's in the list
            if ($fileList -contains $item.Name) {
                $foundFiles += $item.Name
            } else {
                $allFilesFound = $false
            }
        }
    }

    # Display the found files
    Write-Host "Found Files:"
    $foundFiles

    # Display the missing files
    Write-Host "Missing Files:"
    $missingFiles = Compare-Object $fileList $foundFiles -PassThru
    $missingFiles

    return $allFilesFound
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

# Test the installation
$allTestsPassed = $true
try {
    Install-MsiPackage -MsiPath $MsiPath -MsiAdditionalArguments "$MsiAdditionalArguments"
    $allTestsPassed =  CompareFilesInDirectory -targetPath $InstallPath -listFilePath $expectedFileLists[$BuildArtifact]
} catch {
    Write-Host "Error: $_"
}

Pop-Location

if (-not $allTestsPassed) {
    Write-Host "One or more tests FAILED!" -ForegroundColor Red
    exit 1
}
exit 0