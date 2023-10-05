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
    "Build-x64_Debug" = "..\..\scripts\check_msi_installation_msi_files_regular_debug.txt"
    "Build-x64-native-only_NativeOnlyRelease" = "..\..\scripts\check_msi_installation_msi_files_nativeonly_release.txt"
}

function CompareFilesInDirectory {
    param(
        [string]$targetPath,
        [string]$listFilePath
    )

    # Read the list of files from the file containing the expected file list
    $ExpectedFiles = Get-Content $listFilePath

    # Get all files installed in the target directory
    $InstalledFiles = Get-ChildItem -Path $targetPath -File -Recurse | ForEach-Object { $_.FullName }

    # Compare the installed files with the expected binaries
    $MissingFiles = Compare-Object -ReferenceObject $ExpectedFiles -DifferenceObject $InstalledFiles -PassThru | Where-Object { $_.SideIndicator -eq '<=' }
    $ExtraFiles = Compare-Object -ReferenceObject $ExpectedFiles -DifferenceObject $InstalledFiles | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject
    if ($MissingFiles -or $ExtraFiles) {
        Write-Host "Mismatch found between the installed files and the one in the expected list:" -ForegroundColor Red
        Write-Host "Missing Files:" -ForegroundColor Red
        Write-Host $MissingFiles
        Write-Host "Extra Files:" -ForegroundColor Red
        Write-Host $ExtraFiles
        return $false
    } else {
        Write-Host "All installed files match the expected list." -ForegroundColor Green
        return $true
    }
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

    # ```bash
    # # Verify that the eBPF drivers are running:
    # sc.exe query eBPFCore
    # sc.exe query NetEbpfExt

    # # Verify that the netsh extension is operational:
    # netsh ebpf show prog

    # # Run the unit tests, and expect a full pass:
    # cd <eBPF install folder>\testing
    # unit_tests.exe -d yes

    # # Test some additional commands, e.g.:
    # bpftool prog show
    # ```

    $res = Uninstall-MsiPackage -MsiPath $MsiPath
    $allTestsPassed = $allTestsPassed -and $res
} catch {
    $allTestsPassed = $false
    Write-Host "Error: $_"
}

Pop-Location

if (-not $allTestsPassed) {
    Write-Host "One or more tests FAILED!" -ForegroundColor Red
    exit 1
}
exit 0