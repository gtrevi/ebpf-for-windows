# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param ([Parameter(Mandatory=$True)] [string] $WorkingDirectory,
       [Parameter(Mandatory=$True)] [string] $LogFileName)

Push-Location $WorkingDirectory

$BinaryPath = "$env:ProgramFiles\ebpf-for-windows";

Import-Module $PSScriptRoot\common.psm1 -Force -ArgumentList ($LogFileName) -WarningAction SilentlyContinue

# eBPF Drivers.
$EbpfDrivers =
@{
    "EbpfCore" = "ebpfcore.sys";
    "NetEbpfExt" = "netebpfext.sys";
    "SampleEbpfExt" = "sample_ebpf_ext.sys"
}

#
# Uninstall eBPF components.
#
function Unregister-eBPFComponents
{
    # Uninstall drivers.
    $EbpfDrivers.GetEnumerator() | ForEach-Object {
        # New-Service does not support installing drivers.
        sc.exe delete $_.Name 2>&1 | Write-Log
    }

    # Uninstall user mode service.
    sc.exe delete eBPFSvc 2>&1 | Write-Log

    # Delete the eBPF netsh helper.
    netsh delete helper ebpfnetsh.dll 2>&1 | Write-Log
}

#
# Install eBPF components.
#

function Register-eBPFComponents
{
    # Uninstall previous installations (if any).
    Unregister-eBPFComponents

    # Install drivers.
    $EbpfDrivers.GetEnumerator() | ForEach-Object {
        if (Test-Path -Path ("$BinaryPath\{0}" -f $_.Value)) {
            Write-Log ("Installing {0}..." -f $_.Name) -ForegroundColor Green
            # New-Service does not support installing drivers.
            sc.exe create $_.Name type=kernel start=demand binpath=("$BinaryPath\{0}" -f $_.Value) 2>&1 | Write-Log
            if ($LASTEXITCODE -ne 0) {
                throw ("Failed to create $_.Name driver.")
            } else {
                Write-Log ("{0} driver created." -f $_.Name) -ForegroundColor Green
            }
        }
        if (Test-Path -Path ("$BinaryPath\drivers\{0}" -f $_.Value)) {
            Write-Log ("Installing {0}..." -f $_.Name) -ForegroundColor Green
            # New-Service does not support installing drivers.
            sc.exe create $_.Name type=kernel start=demand binpath=("$BinaryPath\drivers\{0}" -f $_.Value) 2>&1 | Write-Log
            if ($LASTEXITCODE -ne 0) {
                throw ("Failed to create $_.Name driver.")
            } else {
                Write-Log ("{0} driver created." -f $_.Name) -ForegroundColor Green
            }
        }
    }

    # Install user mode service.
    if (Test-Path -Path "ebpfsvc.exe") {
        .\eBPFSvc.exe install 2>&1 | Write-Log
        if ($LASTEXITCODE -ne 0) {
            throw ("Failed to create eBPF user mode service.")
        } else {
            Write-Log "eBPF user mode service created." -ForegroundColor Green
        }
    }

    # Add the eBPF netsh helper.
    netsh add helper ebpfnetsh.dll 2>&1 | Write-Log
}

function Enable-KMDFVerifier
{
    # Install drivers.
    $EbpfDrivers.GetEnumerator() | ForEach-Object {
        New-Item -Path ("HKLM:\System\CurrentControlSet\Services\{0}\Parameters\Wdf" -f $_.Name) -Force -ErrorAction Stop
        New-ItemProperty -Path ("HKLM:\System\CurrentControlSet\Services\{0}\Parameters\Wdf" -f $_.Name) -Name "VerifierOn" -Value 1 -PropertyType DWord -Force -ErrorAction Stop
        New-ItemProperty -Path ("HKLM:\System\CurrentControlSet\Services\{0}\Parameters\Wdf" -f $_.Name) -Name "TrackHandles" -Value "*" -PropertyType MultiString -Force  -ErrorAction Stop
    }
}

#
# Start service and drivers.
#
function Start-eBPFComponents
{
    param([parameter(Mandatory=$false)] [bool] $Tracing = $false)

    if ($Tracing) {
        Write-Log "Starting ETW tracing"
        Start-Process -FilePath "wpr.exe" -ArgumentList @("-start", "EbpfForWindows.wprp", "-filemode") -NoNewWindow -Wait
    }

    # Start drivers.
    $EbpfDrivers.GetEnumerator() | ForEach-Object {
        if (Test-Path -Path ("$BinaryPath\drivers\{0}" -f $_.Value)) {
            Start-Service $_.Name -ErrorAction Stop | Write-Log
            Write-Host ("{0} Driver started." -f $_.Name)
        }
    }

    if (Test-Path -Path "ebpfsvc.exe") {
        # Start user mode service.
        Start-Service "eBPFSvc" -ErrorAction Stop | Write-Log
        Write-Host "eBPFSvc service started."
    }
}

function Install-eBPFComponents
{
    param([Parameter(Mandatory=$false)] [bool] $Tracing = $false,
          [Parameter(Mandatory=$false)] [bool] $KMDFVerifier = $false,
          [Parameter(Mandatory=$false)] [bool] $UseMsi = $false)

    if ($UseMsi) {

        $res = & Start-Process msiexec.exe -Wait -ArgumentList '/i ebpf-for-windows.msi /quiet /qn /norestart /log install.log ADDLOCAL=ALL'
        if ($res -ne 0) {
            throw ("Failed to install the eBPF MSI.")
        }
    } else {
        # Stop eBPF Components
        Stop-eBPFComponents

        # Copy all binaries to the install folder.
        Copy-Item *.sys -Destination "$BinaryPath\drivers" -Force -ErrorAction Stop 2>&1 | Write-Log
        if (Test-Path -Path "drivers") {
            Copy-Item drivers\*.sys -Destination "$BinaryPath\drivers" -Force -ErrorAction Stop 2>&1 | Write-Log
        }
        if (Test-Path -Path "testing\testing") {
            Copy-Item testing\testing\*.sys -Destination "$BinaryPath\drivers" -Force -ErrorAction Stop 2>&1 | Write-Log
        }
        Copy-Item *.dll -Destination "$BinaryPath" -Force -ErrorAction Stop 2>&1 | Write-Log
        Copy-Item *.exe -Destination "$BinaryPath" -Force -ErrorAction Stop 2>&1 | Write-Log

        # Register all components.
        Register-eBPFComponents
    }

    if ($KMDFVerifier) {
        # Enable KMDF verifier and tag tracking.
        Enable-KMDFVerifier
    }

    # Start all components.
    Start-eBPFComponents -Tracing $Tracing
}

function Stop-eBPFComponents
{
    # Stop user mode service.
    Stop-Service "eBPFSvc" -ErrorAction Ignore 2>&1 | Write-Log

    # Stop the drivers.
    $EbpfDrivers.GetEnumerator() | ForEach-Object {
        Stop-Service $_.Name -ErrorAction Ignore 2>&1 | Write-Log
    }
}

function Uninstall-eBPFComponents
{
    param([Parameter(Mandatory=$false)][boolean] $UseMsi = $false)

    if ($UseMsi) {

        $res = & Start-Process msiexec.exe -Wait -ArgumentList '/x ebpf-for-windows.msi /quiet /qn /norestart /log install.log'
        if ($res -ne 0) {
            throw ("Failed to uninstall the eBPF MSI.")
        }

    } else {

        Stop-eBPFComponents
        Unregister-eBPFComponents
        Remove-Item "$BinaryPath\drivers\*bpf*" -Force -ErrorAction Stop 2>&1 | Write-Log
        Remove-Item "$BinaryPath\*bpf*" -Force -ErrorAction Stop 2>&1 | Write-Log
    }

    wpr.exe -cancel
}
