#powershell.exe -ExecutionPolicy Bypass -File .\AppAllowOnly.ps1 -UserName "Ayaz,Ashar" -Apps "chrome.exe,notepad.exe,WhatsApp.exe"


<#
.SYNOPSIS
  Per-user "Allow-Only" for apps using RestrictRun.

.PARAMETER UserName
  Comma-separated list of local usernames. e.g. "Ayaz,Ashar"

.PARAMETER Apps
  Comma-separated list of executable names to ALLOW. e.g. "chrome.exe,notepad.exe,WhatsApp.exe"

.NOTES
  - Run as Administrator.
  - Users should sign out/in for changes to fully take effect.
#>

param(
    [Parameter(Mandatory=$true)][string]$UserName,
    [Parameter(Mandatory=$true)][string]$Apps
)

function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "This script must be run as Administrator." -ForegroundColor Red
        exit 1
    }
}

function Write-RestrictRun {
    param([string]$HKURoot, [string[]]$AppList)

    $explorerPath = Join-Path $HKURoot "Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $restrictKey  = Join-Path $explorerPath "RestrictRun"

    if (-not (Test-Path $explorerPath)) { New-Item -Path $explorerPath -Force | Out-Null }

    New-ItemProperty -Path $explorerPath -Name "RestrictRun" -Value 1 -PropertyType DWord -Force | Out-Null

    if (-not (Test-Path $restrictKey)) { New-Item -Path $restrictKey -Force | Out-Null }

    # remove numeric entries
    Get-ItemProperty -Path $restrictKey -ErrorAction SilentlyContinue | ForEach-Object {
        $_.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object {
            Remove-ItemProperty -Path $restrictKey -Name $_.Name -ErrorAction SilentlyContinue
        }
    }

    $i = 1
    foreach ($a in $AppList) {
        $exe = $a.Trim()
        if ($exe -ne "") {
            New-ItemProperty -Path $restrictKey -Name ($i.ToString()) -Value $exe -PropertyType String -Force | Out-Null
            Write-Host "    [Allow] $exe as entry #$i"
            $i++
        }
    }
}

Ensure-Admin

$UserList = $UserName -split ",\s*"
$AppList  = $Apps -split ",\s*"

Write-Host "Applying App Allow-Only (RestrictRun)..." -ForegroundColor Cyan

foreach ($u in $UserList) {
    Write-Host "`nProcessing user: $u" -ForegroundColor Yellow

    $localUser = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
    if (-not $localUser) {
        Write-Host "  User '$u' not found. Skipping." -ForegroundColor Red
        continue
    }
    $sid = $localUser.SID.Value
    $hkuPath = "HKU:\$sid"

    if (Test-Path $hkuPath) {
        Write-Host "  Hive loaded for $u. Writing directly..." -ForegroundColor Green
        Write-RestrictRun -HKURoot $hkuPath -AppList $AppList
        continue
    }

    # Try to load NTUSER.DAT (if user not signed in)
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
        Write-RestrictRun -HKURoot ("HKU:\" + $tempKey) -AppList $AppList

        # export and import under real SID so it persists under HKU\<SID>
        $exportFile = Join-Path $env:TEMP "$tempKey-RestrictRun.reg"
        $subKey = "HKU\\$tempKey\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer"
        & reg.exe export $subKey $exportFile /y | Out-Null

        if (Test-Path $exportFile) {
            (Get-Content $exportFile) -replace "HKEY_USERS\\$tempKey", "HKEY_USERS\\$sid" | Set-Content $exportFile
            & reg.exe import $exportFile | Out-Null
            Remove-Item $exportFile -Force -ErrorAction SilentlyContinue
            Write-Host "  RestrictRun applied into real SID $sid." -ForegroundColor Green
        } else {
            Write-Host "  Warning: Export failed; changes might not persist. Please run when user is signed in." -ForegroundColor Yellow
        }
    } finally {
        & reg.exe unload "HKU\$tempKey" | Out-Null
    }
}

Write-Host "`nCompleted. Users must sign out and sign back in for full effect." -ForegroundColor Cyan
