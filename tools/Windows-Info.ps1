# Windows installation and license inventory
# Saves a text report to <USB root>\Reports\Windows when run from tools\.
# Falls back to the current user's Desktop if the USB root cannot be resolved.

$ErrorActionPreference = "SilentlyContinue"

function Get-RegistryProductKey {
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $digitalProductId = (Get-ItemProperty -Path $regPath -Name DigitalProductId).DigitalProductId
        if (-not $digitalProductId) { return $null }

        $keyOffset = 52
        $chars = "BCDFGHJKMPQRTVWXY2346789"
        $isWin8 = ([math]::Truncate($digitalProductId[66] / 6)) -band 1
        $digitalProductId[66] = ($digitalProductId[66] -band 0xF7) -bor (($isWin8 -band 2) * 4)

        $key = ""
        $last = 0

        for ($i = 24; $i -ge 0; $i--) {
            $current = 0
            for ($j = 14; $j -ge 0; $j--) {
                $current = ($current * 256) -bxor $digitalProductId[$j + $keyOffset]
                $digitalProductId[$j + $keyOffset] = [math]::Truncate($current / 24)
                $current = $current % 24
            }

            $key = $chars[$current] + $key
            $last = $current
        }

        if ($isWin8 -eq 1) {
            $keyPart1 = $key.Substring(1, $last)
            $keyPart2 = $key.Substring($last + 1)
            $key = $keyPart1 + "N" + $keyPart2
        }

        return (($key -split '(.{5})' | Where-Object { $_ }) -join '-').TrimEnd('-')
    }
    catch {
        return $null
    }
}

function Get-ActivationStatus([int]$Status) {
    switch ($Status) {
        0 { "Unlicensed" }
        1 { "Licensed / Activated" }
        2 { "OOB Grace" }
        3 { "OOT Grace" }
        4 { "Non-Genuine Grace" }
        5 { "Notification" }
        6 { "Extended Grace" }
        default { "Unknown" }
    }
}

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$slService = Get-CimInstance SoftwareLicensingService
$license = Get-CimInstance SoftwareLicensingProduct |
    Where-Object {
        $_.PartialProductKey -and
        $_.Name -like "Windows*"
    } |
    Sort-Object LicenseStatus -Descending |
    Select-Object -First 1

$reg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

$oemKey = $slService.OA3xOriginalProductKey
$registryKey = Get-RegistryProductKey

if ([string]::IsNullOrWhiteSpace($oemKey)) {
    $oemKey = "(not present in BIOS/UEFI)"
}

if ([string]::IsNullOrWhiteSpace($registryKey)) {
    $registryKey = "(not recoverable from registry)"
}

$activation = if ($license) {
    Get-ActivationStatus ([int]$license.LicenseStatus)
} else {
    "Unknown"
}

$installDate = ""
if ($os.InstallDate) {
    try {
        $installDate = ([Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate)).ToString("yyyy-MM-dd HH:mm:ss")
    } catch {
        try { $installDate = ([datetime]$os.InstallDate).ToString("yyyy-MM-dd HH:mm:ss") } catch {}
    }
}

# When this script is stored in <USB>\tools\, save reports under <USB>\Reports\Windows.
$toolkitRoot = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $toolkitRoot "Reports\Windows"

try {
    New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
}
catch {
    $reportDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "Windows-Reports"
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeComputerName = ($env:COMPUTERNAME -replace '[^A-Za-z0-9._-]', '_')
$reportFile = Join-Path $reportDir ($safeComputerName + "_" + $timestamp + ".txt")

$report = @"
Windows Installation / License Report
=====================================

Generated:              $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

COMPUTER
--------
Computer Name:          $env:COMPUTERNAME
Manufacturer:           $($cs.Manufacturer)
Model:                  $($cs.Model)
Serial Number:          $($bios.SerialNumber)
Current User:           $env:USERNAME

WINDOWS
-------
Edition:                $($os.Caption)
Display Version:        $($reg.DisplayVersion)
Release ID:             $($reg.ReleaseId)
Build:                  $($os.BuildNumber)
UBR:                    $($reg.UBR)
Architecture:           $($os.OSArchitecture)
Install Date:           $installDate
Product ID:             $($reg.ProductId)

LICENSE / ACTIVATION
--------------------
Activation Status:      $activation
License Name:           $($license.Name)
License Description:    $($license.Description)
Partial Installed Key:  $($license.PartialProductKey)

FULL KEY BACKUP
---------------
OEM BIOS/UEFI Key:      $oemKey
Registry Decoded Key:   $registryKey

NOTES
-----
- OEM BIOS/UEFI Key is the full firmware-embedded Windows key when the PC has one.
- Registry Decoded Key is a best-effort recovery of the key stored by Windows.
- On Windows 10/11 with Digital License, the decoded registry key can be a generic
  installation key and may not be the unique key that originally activated Windows.
- Keep this report secure because it may contain a full Windows product key.
"@

$report | Set-Content -Path $reportFile -Encoding UTF8

Write-Host ""
Write-Host "Windows information saved successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Report:"
Write-Host $reportFile -ForegroundColor Cyan
Write-Host ""
Write-Host "OEM BIOS/UEFI Key: $oemKey"
Write-Host "Registry Decoded Key: $registryKey"
Write-Host ""
