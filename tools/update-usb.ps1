param(
    [string]$Target = (Split-Path -Parent $PSScriptRoot),
    [string]$Profile = "full",
    [switch]$All,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ToolkitRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $ToolkitRoot "config\manifest.json"
if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$Target = [System.IO.Path]::GetFullPath($Target)
New-Item -ItemType Directory -Path $Target -Force | Out-Null
$StateFile = Join-Path $Target "config\.iso-state.tsv"

Write-Host "IT Toolkit USB updater"
Write-Host "Target : $Target"
if ($All) {
    Write-Host "Profile: ALL enabled components"
} else {
    Write-Host "Profile: $Profile"
}
Write-Host ""

function Update-ToolkitFiles {
    $pkg = $Manifest.updater.toolkit_package
    if (-not $pkg) { return }

    $localHashFile = Join-Path $Target ([string]$pkg.local_hash_file)
    New-Item -ItemType Directory -Path (Split-Path -Parent $localHashFile) -Force | Out-Null

    Write-Host "[TOOLKIT] Checking configuration/tools package..."

    try {
        $remoteText = (Invoke-WebRequest -Uri ([string]$pkg.sha256_url) -UseBasicParsing -TimeoutSec 45).Content
        $remoteSha = (($remoteText -split '\s+')[0]).ToLowerInvariant()
    } catch {
        Write-Warning "Toolkit package checksum unavailable. Keeping local toolkit files."
        return
    }

    if ($remoteSha -notmatch '^[0-9a-f]{64}$') {
        Write-Warning "Invalid toolkit package checksum. Keeping local toolkit files."
        return
    }

    $localSha = ""
    if (Test-Path $localHashFile) {
        $localSha = (((Get-Content $localHashFile -Raw) -split '\s+')[0]).ToLowerInvariant()
    }

    if (-not $Force -and $localSha -eq $remoteSha) {
        Write-Host "[OK]   Toolkit files already current."
        return
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("it-toolkit-" + [guid]::NewGuid().ToString() + ".tar.gz")
    $stage = Join-Path ([IO.Path]::GetTempPath()) ("it-toolkit-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    try {
        Write-Host "       Downloading toolkit package..."
        Download-LargeFile ([string]$pkg.url) $tmp

        $actual = (Get-FileHash -Algorithm SHA256 $tmp).Hash.ToLowerInvariant()
        if ($actual -ne $remoteSha) {
            throw "Toolkit package SHA-256 mismatch"
        }

        tar.exe -xzf $tmp -C $stage
        if ($LASTEXITCODE -ne 0) { throw "Could not extract toolkit package" }

        Copy-Item (Join-Path $stage "*") $Target -Recurse -Force
        Set-Content -Path $localHashFile -Value ($remoteSha + "  it-toolkit-files.tar.gz") -Encoding ASCII

        $script:ManifestPath = Join-Path $Target "config\manifest.json"
        $script:Manifest = Get-Content $script:ManifestPath -Raw | ConvertFrom-Json
        Write-Host "[OK]   Toolkit configuration, tools, rootfs and Ventoy files updated."
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-NaturalKey([string]$Value) {
    return [regex]::Replace($Value, '\d+', { param($m) $m.Value.PadLeft(12, '0') })
}

function Resolve-DownloadUrl($Component) {
    $Provider = [string]$Component.download.provider
    $Base = [string]$Component.download.url

    switch ($Provider) {
        "debian" {
            $sums = (Invoke-WebRequest "$Base/SHA256SUMS" -UseBasicParsing).Content
            $matches = [regex]::Matches($sums, 'debian-13\.[0-9.]+-amd64-netinst\.iso')
            if ($matches.Count -eq 0) { throw "Could not resolve current Debian netinst" }
            $names = $matches.Value | Sort-Object { Get-NaturalKey $_ } -Unique
            return "$Base/$($names[-1])"
        }
        "systemrescue" {
            $html = (Invoke-WebRequest $Base -UseBasicParsing).Content
            $matches = [regex]::Matches($html, 'systemrescue-[0-9]+\.[0-9]+-amd64\.iso')
            if ($matches.Count -eq 0) { throw "Could not resolve current SystemRescue ISO" }
            $names = $matches.Value | Sort-Object { Get-NaturalKey $_ } -Unique
            $name = $names[-1]
            $version = $name -replace '^systemrescue-', '' -replace '-amd64\.iso$', ''
            return "https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/$version/$name/download"
        }
        "rescuezilla" {
            $headers = @{ "User-Agent" = "IT-Toolkit-USB" }
            $release = Invoke-RestMethod -Uri $Base -Headers $headers
            $urls = @($release.assets | ForEach-Object { $_.browser_download_url })
            $preferred = @($urls | Where-Object { $_ -match '(?i)64bit.*\.iso$' -and $_ -notmatch '(?i)alternative' })
            if ($preferred.Count -eq 0) {
                $preferred = @($urls | Where-Object { $_ -match '(?i)64bit.*\.iso$' })
            }
            if ($preferred.Count -eq 0) {
                $preferred = @($urls | Where-Object { $_ -match '(?i)\.iso$' })
            }
            if ($preferred.Count -eq 0) { throw "Could not resolve current Rescuezilla ISO" }
            return [string]$preferred[0]
        }
        "clonezilla" {
            $html = (Invoke-WebRequest $Base -UseBasicParsing).Content
            $matches = [regex]::Matches($html, 'clonezilla_live_stable/([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)')
            if ($matches.Count -eq 0) { throw "Could not resolve current Clonezilla stable release" }
            $versions = @($matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object { Get-NaturalKey $_ } -Unique)
            $version = $versions[-1]
            $name = "clonezilla-live-$version-amd64.iso"
            return "https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/$version/$name/download"
        }
        "proxmox" {
            $html = (Invoke-WebRequest $Base -UseBasicParsing).Content
            $matches = [regex]::Matches($html, 'proxmox-ve_[0-9][0-9A-Za-z._-]*\.iso')
            if ($matches.Count -eq 0) { throw "Could not resolve current Proxmox VE ISO" }
            $names = @($matches.Value | Sort-Object { Get-NaturalKey $_ } -Unique)
            return "$Base$($names[-1])"
        }
        default {
            if ([string]::IsNullOrWhiteSpace($Base)) { throw "No download URL for $($Component.name)" }
            return $Base
        }
    }
}

function Resolve-ExpectedSha256($Component, [string]$ResolvedUrl) {
    if ($Component.checksum.value) {
        return ([string]$Component.checksum.value).ToLowerInvariant()
    }

    if ([string]$Component.download.provider -eq "debian") {
        $base = [string]$Component.download.url
        $sourceName = [System.IO.Path]::GetFileName(([Uri]$ResolvedUrl).AbsolutePath)
        $sums = (Invoke-WebRequest "$base/SHA256SUMS" -UseBasicParsing).Content
        foreach ($line in ($sums -split "\r?\n")) {
            if ($line -match '^([a-fA-F0-9]{64})\s+\*?(.+)$' -and $Matches[2] -eq $sourceName) {
                return $Matches[1].ToLowerInvariant()
            }
        }
    }

    return ""
}

function Get-RemoteSignature([string]$Url) {
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 -UseBasicParsing
        $effective = ""
        try { $effective = $r.BaseResponse.ResponseUri.AbsoluteUri } catch {}
        $etag = [string]$r.Headers["ETag"]
        $modified = [string]$r.Headers["Last-Modified"]
        $length = [string]$r.Headers["Content-Length"]

        if ([string]::IsNullOrWhiteSpace($etag + $modified + $length)) {
            return ""
        }
        return "$effective|$etag|$modified|$length"
    } catch {
        return ""
    }
}

function Get-State([string]$Id) {
    if (-not (Test-Path $StateFile)) { return "" }
    foreach ($line in Get-Content $StateFile) {
        $parts = $line -split [char]9, 3
        if ($parts.Count -ge 2 -and $parts[0] -eq $Id) {
            return $parts[1]
        }
    }
    return ""
}

function Set-State([string]$Id, [string]$Signature, [string]$Sha256) {
    $lines = @()
    if (Test-Path $StateFile) {
        $lines = @(Get-Content $StateFile | Where-Object {
            $p = $_ -split [char]9, 2
            $p[0] -ne $Id
        })
    }
    $lines += ($Id + [char]9 + $Signature + [char]9 + $Sha256)
    Set-Content -Path $StateFile -Value $lines -Encoding UTF8
}

function Download-LargeFile([string]$Url, [string]$Path) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source -fL --retry 3 --retry-delay 2 -C - -o $Path $Url
        if ($LASTEXITCODE -ne 0) { throw "curl.exe failed with exit code $LASTEXITCODE" }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing
    }
}

if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) { throw "tar.exe is required to update toolkit files" }

Update-ToolkitFiles

$components = @($Manifest.components | Where-Object {
    $_.enabled -eq $true -and
    $_.download.enabled -eq $true -and
    ($All -or ($_.profiles -contains $Profile))
})

foreach ($c in $components) {
    $id = [string]$c.id
    $name = [string]$c.name
    $filename = [string]$c.filename

    Write-Host "[$id] $name"

    if (-not $filename.EndsWith("_VTNORMAL.iso", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest filename does not end in _VTNORMAL.iso: $filename"
    }

    $destDir = Join-Path $Target ([string]$c.destination)
    $destFile = Join-Path $destDir $filename
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    try {
        $resolved = if ([string]$c.download.method -eq "dynamic") {
            Resolve-DownloadUrl $c
        } else {
            [string]$c.download.url
        }
    } catch {
        if ($c.checksum.required -eq $true) { throw }
        Write-Warning $_
        Write-Host ""
        continue
    }

    $expectedSha = Resolve-ExpectedSha256 $c $resolved

    if ([string]::IsNullOrWhiteSpace($expectedSha) -and $c.checksum.url) {
        try {
            $remoteText = (Invoke-WebRequest -Uri ([string]$c.checksum.url) -UseBasicParsing -TimeoutSec 30).Content
            $expectedSha = (($remoteText -split '\s+')[0]).ToLowerInvariant()
        } catch {
            $expectedSha = ""
        }
    }

    $shaPath = $destFile -replace '\.iso
    $oldSignature = Get-State $id

    if (-not $Force -and (Test-Path $destFile) -and
        -not [string]::IsNullOrWhiteSpace($signature) -and
        $signature -eq $oldSignature) {
        Write-Host "[OK]   Already current: $filename"
        Write-Host ""
        continue
    }

    $part = "$destFile.part"
    Write-Host "       Source: $resolved"
    Write-Host "       Saving: $destFile"

    try {
        Download-LargeFile $resolved $part
    } catch {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        if ($c.checksum.required -eq $true) { throw }
        Write-Warning "Download failed for $name : $_"
        Write-Host ""
        continue
    }

    $actualSha = (Get-FileHash -Algorithm SHA256 $part).Hash.ToLowerInvariant()

    if (-not [string]::IsNullOrWhiteSpace($expectedSha) -and $actualSha -ne $expectedSha) {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch for $name"
    }

    if ($c.checksum.required -eq $true -and [string]::IsNullOrWhiteSpace($expectedSha)) {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        throw "Checksum required but unavailable for $name"
    }

    Move-Item $part $destFile -Force
    $shaPath = $destFile -replace '\.iso$', '.sha256'
    Set-Content -Path $shaPath -Value ($actualSha + "  " + $filename) -Encoding ASCII
    Set-State $id $signature $actualSha

    Write-Host "[OK]   Updated: $filename"
    if (-not [string]::IsNullOrWhiteSpace($expectedSha)) {
        Write-Host "[OK]   SHA-256 verified"
    }
    Write-Host ""
}

Write-Host "Toolkit update complete."
, '.sha256'
    if (-not $Force -and (Test-Path $destFile) -and -not [string]::IsNullOrWhiteSpace($expectedSha)) {
        $localSaved = ""
        if (Test-Path $shaPath) {
            $localSaved = ((((Get-Content $shaPath -Raw) -split '\s+')[0])).ToLowerInvariant()
        }

        if ($localSaved -eq $expectedSha) {
            Write-Host "[OK]   Already current (SHA-256): $filename"
            Write-Host ""
            continue
        }

        if ([string]::IsNullOrWhiteSpace($localSaved)) {
            Write-Host "       No local checksum; verifying existing ISO once..."
            $localActual = (Get-FileHash -Algorithm SHA256 $destFile).Hash.ToLowerInvariant()
            if ($localActual -eq $expectedSha) {
                Set-Content -Path $shaPath -Value ($localActual + "  " + $filename) -Encoding ASCII
                Write-Host "[OK]   Existing ISO matches remote SHA-256."
                Write-Host ""
                continue
            }
        }
    }
    elseif (-not $Force -and (Test-Path $destFile) -and $c.checksum.url -and [string]::IsNullOrWhiteSpace($expectedSha)) {
        Write-Warning "Remote checksum unavailable; keeping existing ISO."
        Write-Host ""
        continue
    }

    $signature = Get-RemoteSignature $resolved
    $oldSignature = Get-State $id

    if (-not $Force -and (Test-Path $destFile) -and
        -not [string]::IsNullOrWhiteSpace($signature) -and
        $signature -eq $oldSignature) {
        Write-Host "[OK]   Already current: $filename"
        Write-Host ""
        continue
    }

    $part = "$destFile.part"
    Write-Host "       Source: $resolved"
    Write-Host "       Saving: $destFile"

    try {
        Download-LargeFile $resolved $part
    } catch {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        if ($c.checksum.required -eq $true) { throw }
        Write-Warning "Download failed for $name : $_"
        Write-Host ""
        continue
    }

    $actualSha = (Get-FileHash -Algorithm SHA256 $part).Hash.ToLowerInvariant()

    if (-not [string]::IsNullOrWhiteSpace($expectedSha) -and $actualSha -ne $expectedSha) {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch for $name"
    }

    if ($c.checksum.required -eq $true -and [string]::IsNullOrWhiteSpace($expectedSha)) {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        throw "Checksum required but unavailable for $name"
    }

    Move-Item $part $destFile -Force
    $shaPath = $destFile -replace '\.iso$', '.sha256'
    Set-Content -Path $shaPath -Value $actualSha -Encoding ASCII
    Set-State $id $signature $actualSha

    Write-Host "[OK]   Updated: $filename"
    if (-not [string]::IsNullOrWhiteSpace($expectedSha)) {
        Write-Host "[OK]   SHA-256 verified"
    }
    Write-Host ""
}

Write-Host "Toolkit update complete."
