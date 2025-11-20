#powershell.exe -ExecutionPolicy Bypass -File .\WebAllowOnly.ps1 -UserName "Ayaz,Ashar" -Websites "facebook.com,instagram.com,twitter.com"


<#
.SYNOPSIS
  Per-user "Allow-Only" web access by setting a non-functional system proxy and bypass list.

.PARAMETER UserName
  Comma-separated local usernames. e.g. "Ayaz,Ashar"

.PARAMETER Websites
  Comma-separated domains that should be ALLOWED. e.g. "facebook.com,instagram.com"

.NOTES
  - Run as Administrator.
  - Users must sign out/in for changes to fully apply. Applies to apps using system proxy.
#>

param(
    [Parameter(Mandatory=$true)][string]$UserName,
    [Parameter(Mandatory=$true)][string]$Websites
)

function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "This script must be run as Administrator." -ForegroundColor Red
        exit 1
    }
}

Ensure-Admin

$UserList = $UserName -split ",\s*"
$AllowList = $Websites -split ",\s*"

# Build ProxyOverride; include both exact and wildcard subdomains
$override = @()
foreach ($d in $AllowList) {
    $dom = $d.Trim()
    if ($dom -ne "") {
        $override += ("*." + $dom)
        $override += $dom
    }
}
$override += "localhost"
$override += "127.0.0.1"
$override += "<local>"
$proxyOverride = ($override -join ";")

# Use a non-responsive local proxy so non-bypassed sites fail
$proxyServer = "127.0.0.1:9"

Write-Host "Applying Web Allow-Only (Proxy method)..." -ForegroundColor Cyan
Write-Host " ProxyServer = $proxyServer" -ForegroundColor Yellow
Write-Host " ProxyOverride = $proxyOverride" -ForegroundColor Yellow

foreach ($u in $UserList) {
    Write-Host "`nProcessing user: $u" -ForegroundColor Yellow

    $localUser = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
    if (-not $localUser) {
        Write-Host "  User '$u' not found. Skipping." -ForegroundColor Red
        continue
    }
    $sid = $localUser.SID.Value
    $hkuPath = "HKU:\$sid"

    $setProxy = {
        param($root)
        $inet = Join-Path $root "Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        if (-not (Test-Path $inet)) { New-Item -Path $inet -Force | Out-Null }
        New-ItemProperty -Path $inet -Name "ProxyEnable" -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $inet -Name "ProxyServer" -PropertyType String -Value $using:proxyServer -Force | Out-Null
        New-ItemProperty -Path $inet -Name "ProxyOverride" -PropertyType String -Value $using:proxyOverride -Force | Out-Null
    }

    if (Test-Path $hkuPath) {
        Write-Host "  Hive loaded for $u. Writing proxy settings..." -ForegroundColor Green
        & $setProxy $hkuPath
        continue
    }

    # Try to load NTUSER.DAT for offline user
    $profile = (Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$sid'" -ErrorAction SilentlyContinue).LocalPath
    if (-not $profile) { $profile = Join-Path -Path $env:SystemDrive -ChildPath "Users\$u" }
    $ntuser = Join-Path $profile "NTUSER.DAT"

    if (-not (Test-Path $ntuser)) {
        Write-Host "  NTUSER.DAT not found at $ntuser. Ask user to sign in once or create profile. Skipping." -ForegroundColor Red
        continue
    }

    $tempKey = "TempHive_$($sid.Replace('-',''))"
    Write-Host "  Loading hive: $ntuser -> HKEY_USERS\$tempKey" -ForegroundColor Cyan
    $loadOut = & reg.exe load "HKU\$tempKey" "$ntuser" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to load hive: $loadOut" -ForegroundColor Red
        continue
    }

    try {
        & $setProxy ("HKU:\" + $tempKey)

        # Export & import to real SID
        $exportFile = Join-Path $env:TEMP "$tempKey-InternetSettings.reg"
        $subKey = "HKU\\$tempKey\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings"
        & reg.exe export $subKey $exportFile /y | Out-Null
        if (Test-Path $exportFile) {
            (Get-Content $exportFile) -replace "HKEY_USERS\\$tempKey", "HKEY_USERS\\$sid" | Set-Content $exportFile
            & reg.exe import $exportFile | Out-Null
            Remove-Item $exportFile -Force -ErrorAction SilentlyContinue
            Write-Host "  Proxy settings applied for SID $sid." -ForegroundColor Green
        } else {
            Write-Host "  Warning: export failed; changes might not persist for SID $sid." -ForegroundColor Yellow
        }
    } finally {
        & reg.exe unload "HKU\$tempKey" | Out-Null
    }
}

Write-Host "`nCompleted. Users must sign out and sign back in for changes to fully take effect." -ForegroundColor Cyan
Write-Host "Note: This method only affects apps that honor system proxy settings." -ForegroundColor Magenta
