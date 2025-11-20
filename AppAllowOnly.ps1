<#
.SYNOPSIS
  Per-user "Allow-Only" for apps using RestrictRun.

.DESCRIPTION
  For each username provided, creates/updates:
    HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\RestrictRun
  and sets RestrictRun = 1, then adds numeric entries with the allowed exe names.
  If the user's hive isn't loaded (user not signed-in), the script will attempt to
  load the user's NTUSER.DAT, write the keys under a temporary HKEY_USERS node,
  export and import those keys under the real SID, then unload.

USAGE
  - Run as Administrator.
  - Example:
      $env:USERS="Ayaz,Ashar"
      $env:APPS="chrome.exe,notepad.exe,WhatsApp.exe"
      powershell -ExecutionPolicy Bypass -File .\AppAllowOnly.ps1

PARAMETERS (via env vars)
  $env:USERS - comma separated list of local usernames
  $env:APPS  - comma separated list of executable names to ALLOW (e.g. chrome.exe)
#>

# -------------------- Helpers --------------------
function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "This script must be run as Administrator." -ForegroundColor Red
        exit 1
    }
}

function Write-RestrictRunToHKU {
    param(
        [string]$HKURoot,         # e.g. "HKU:\S-1-5-21-..."
        [string[]]$AppList
    )
    $explorerPath = Join-Path $HKURoot "Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $restrictKey  = Join-Path $explorerPath "RestrictRun"

    if (-not (Test-Path $explorerPath)) { New-Item -Path $explorerPath -Force | Out-Null }

    # Enable RestrictRun (DWORD = 1)
    New-ItemProperty -Path $explorerPath -Name "RestrictRun" -Value 1 -PropertyType DWord -Force | Out-Null

    if (-not (Test-Path $restrictKey)) { New-Item -Path $restrictKey -Force | Out-Null }

    # Remove numeric entries first
    Get-ItemProperty -Path $restrictKey -ErrorAction SilentlyContinue | ForEach-Object {
        $_.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object {
            Remove-ItemProperty -Path $restrictKey -Name $_.Name -ErrorAction SilentlyContinue
        }
    }

    # Add allowed apps as "1","2",...
    $i = 1
    foreach ($a in $AppList) {
        $trim = $a.Trim()
        if ($trim -ne "") {
            New-ItemProperty -Path $restrictKey -Name ($i.ToString()) -Value $trim -PropertyType String -Force | Out-Null
            Write-Host "  [Added] $trim as allow-entry #$i"
            $i++
        }
    }
}

# -------------------- Main --------------------
Ensure-Admin

# Read env vars (fail if missing)
if (-not $env:USERS -or -not $env:APPS) {
    Write-Host "Usage example (PowerShell):" -ForegroundColor Cyan
    Write-Host '  $env:USERS="Ayaz,Ashar"; $env:APPS="chrome.exe,notepad.exe"; powershell -ExecutionPolicy Bypass -File .\AppAllowOnly.ps1' -ForegroundColor Yellow
    exit 1
}

$users = $env:USERS -split ",\s*"
$appList = $env:APPS -split ",\s*"

Write-Host "Applying App Allow-Only policy..." -ForegroundColor Cyan

foreach ($u in $users) {
    Write-Host "`nProcessing user: $u" -ForegroundColor Yellow

    $localUser = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
    if (-not $localUser) {
        Write-Host "  User '$u' not found locally. Skipping." -ForegroundColor Red
        continue
    }
    $sid = $localUser.SID.Value
    $hkuPath = "HKU:\$sid"

    if (Test-Path $hkuPath) {
        Write-Host "  Hive loaded for $u (SID $sid). Writing directly..." -ForegroundColor Green
        Write-RestrictRunToHKU -HKURoot $hkuPath -AppList $appList
        continue
    }

    # Attempt to load user's NTUSER.DAT
    $profilePath = (Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$sid'" -ErrorAction SilentlyContinue).LocalPath
    if (-not $profilePath) {
        # fallback to default Users folder
        $profilePath = Join-Path -Path $env:SystemDrive -ChildPath "Users\$u"
    }
    $ntuser = Join-Path -Path $profilePath -ChildPath "NTUSER.DAT"

    if (-not (Test-Path $ntuser)) {
        Write-Host "  Could not locate NTUSER.DAT for $u at $ntuser. Please ensure the user has a profile or ask them to sign in once." -ForegroundColor Red
        continue
    }

    $tempKey = "TempHive_$($sid.Replace('-',''))"
    Write-Host "  Loading hive from: $ntuser to HKEY_USERS\$tempKey" -ForegroundColor Cyan
    $load = & reg.exe load "HKU\$tempKey" "$ntuser" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to load hive: $load" -ForegroundColor Red
        continue
    }

    try {
        # Write to temp hive
        Write-RestrictRunToHKU -HKURoot ("HKU:\" + $tempKey) -AppList $appList

        # Export the subtree and import under the real SID
        $exportFile = Join-Path $env:TEMP "$tempKey-RestrictRun.reg"
        $subKey = "HKU\\$tempKey\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer"
        & reg.exe export $subKey $exportFile /y | Out-Null
        if (Test-Path $exportFile) {
            (Get-Content $exportFile) -replace "HKEY_USERS\\$tempKey", "HKEY_USERS\\$sid" | Set-Content $exportFile
            & reg.exe import $exportFile | Out-Null
            Remove-Item $exportFile -Force -ErrorAction SilentlyContinue
            Write-Host "  RestrictRun applied to real SID $sid." -ForegroundColor Green
        } else {
            Write-Host "  Warning: export file not created, changes may not be persisted for SID $sid." -ForegroundColor Yellow
        }
    } finally {
        & reg.exe unload "HKU\$tempKey" | Out-Null
    }
}

Write-Host "`nAll done. Users must sign out and sign back in for RestrictRun to take effect." -ForegroundColor Cyan
Write-Host "For immediate effect for a signed-in user, you can restart Explorer (careful):" -ForegroundColor Yellow
Write-Host "  taskkill /IM explorer.exe /F & start explorer.exe" -ForegroundColor Yellow
