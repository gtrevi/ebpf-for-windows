# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param (
        [Parameter(Mandatory=$true)] [string]$BuildArtifact,
        [Parameter(Mandatory=$true)] [string]$MsiPath)

Push-Location $WorkingDirectory

$InstallPath = "$env:ProgramFiles\ebpf-for-windows";

# Define the additional arguments to pass to the MSI installer for each build artifact
$installComponents = @{
    "Build-x64_Debug" = "ADDLOCAL=eBPF_Runtime_Components,eBPF_Runtime_Components_JIT,eBPF_Development,eBPF_Testing"
    "Build-x64-native-only_NativeOnlyRelease" = "ADDLOCAL=eBPF_Runtime_Components"
}

# Define the expected file lists for each build artifact
$expectedFileLists = @{
    "Build-x64_Debug" = "..\..\scripts\check_msi_installation_files_regular_debug.txt"
    "Build-x64-native-only_NativeOnlyRelease" = "..\..\scripts\check_msi_installation_files_nativeonly_release.txt"
}

# Define a list of eBPF drivers to check
$EbpfDrivers =
@{
    "EbpfCore" = "ebpfcore.sys";
    "NetEbpfExt" = "netebpfext.sys";
}
$eBpfExtensionName = "ebpfnetsh"
$eBpfServiceName = "ebpfsvc"

function CompareFilesInDirectory {
    param(
        [string]$targetPath,
        [string]$listFilePath
    )

    Write-Host "Comparing files in '$targetPath' with the expected list in '$listFilePath'..."

    # Get all files installed in the target directory
    $InstalledFiles = Get-ChildItem -Path $targetPath -File -Recurse | ForEach-Object { $_.FullName }

    # Read the list of files from the file containing the expected file list
    $ExpectedFiles = Get-Content $listFilePath

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

    Write-Host "Installing MSI package with arguments: '$arguments'..."
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

    Write-Host "Uninstalling MSI package..."
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

function Get-FullDiskPathFromService {
    param (
        [string]$serviceName
    )

    Write-Log -level $LogLevelInfo -message "Get-FullDiskPathFromService($serviceName)"

    $scQueryOutput = & "sc.exe" qc $serviceName

    # Search for the BINARY_PATH_NAME line using regex.
    $binaryPathLine = $scQueryOutput -split "`n" | Where-Object { $_ -match "BINARY_PATH_NAME\s+:\s+(.*)" }

    if ($binaryPathLine) {

        # Extract the full disk path using regex.
        $binaryPath = $matches[1]
        $fullDiskPath = [regex]::Match($binaryPath, '(?<=\\)\w:.+')

        if ($fullDiskPath.Success) {
            return $fullDiskPath.Value
        }
    }

    return $null
}

function Check-eBPF-Installation {

    $res = $true

    # Check if the eBPF drivers are registered correctly.
    Write-Host "Checking if the eBPF drivers are registered correctly..."
    try {
        $EbpfDrivers.GetEnumerator() | ForEach-Object {
            $driverName = $_.Key
            $currDriverPath = Get-FullDiskPathFromService -serviceName $driverName
            if ($currDriverPath) {
                if ($?) {
                    Write-Log -level $LogLevelInfo -message "[$driverName] is registered correctly, starting the driver service..."
                } else {
                    Write-Log -level $LogLevelError -message "[$driverName] is NOT registered correctly!"
                    $res = $false
                }
            }
        }
    }
    catch {
        Write-Log -level $LogLevelError -message "An error occurred while starting the eBPF drivers: $_"
        $res = $false
    }

    # Run netsh command, capture the output, and check if the output contains information about the extension.
    $output = netsh $eBpfExtensionName show helper
    if ($output -match "The following commands are available:") {
        Write-Host "The '$eBpfExtensionName' netsh extension is correctly registered."
    } else {
        Write-Host "The '$eBpfExtensionName' netsh extension is NOT registered."
        Write-Host "Output of 'netsh $eBpfExtensionName show helper':"
        Write-Host $output
        $res = $false
    }

    # If the JIT option is enabled, check if the eBPF JIT service is running.
    if ($installComponents[$BuildArtifact] -like "*eBPF_Runtime_Components_JIT*") {
        Write-Host "Checking if the eBPF JIT service is running..."
        $service = Get-Service -Name $eBpfServiceName
        if ($service.Status -eq "Running") {
            Write-Host "The eBPF JIT service is running."
        } else {
            Write-Host "The eBPF JIT service is NOT running."
            $res = $false
        }
    }

    return $res
}


# Test the MSI package
$allTestsPassed = $true
try {
    # Install the MSI package
    $allTestsPassed = Install-MsiPackage -MsiPath "$MsiPath" -MsiAdditionalArguments $installComponents[$BuildArtifact]

    # Check if the files are installed correctly
    $res =  CompareFilesInDirectory -targetPath "$InstallPath" -listFilePath $expectedFileLists[$BuildArtifact]
    $allTestsPassed = $allTestsPassed -and $res

    # Check if the eBPF drivers and netsh extension are registered correctly.
    $res = Check-eBPF-Installation
    $allTestsPassed = $allTestsPassed -and $res

    # Uninstall the MSI package
    $res = Uninstall-MsiPackage -MsiPath "$MsiPath"
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