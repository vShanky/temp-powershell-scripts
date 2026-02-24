# # Block multiple apps
# .\EnhancedAppBlocker.ps1 -AppNames chrome, spotify, notepad++, calculator

# # Block with extensions
# .\EnhancedAppBlocker.ps1 -AppNames "chrome.exe", "spotify.exe"

# # Try to block Microsoft Store apps
# .\EnhancedAppBlocker.ps1 -AppNames "netflix", "spotify", "microsoft.windows calculator"



# Enhanced App Blocker.ps1
param (
    [Parameter(Mandatory = $true)]
    [string[]]$AppNames,
    
    [Parameter(Mandatory = $false)]
    [switch]$Unblock
)

# Run as Administrator check
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script requires Administrator privileges. Please run PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

# Configuration
$DebuggerPath = 'mshta.exe "javascript:alert(''This application has been blocked by your administrator.'');close();"'

function Block-Executable {
    param([string]$ExeName)
    
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$ExeName"
    
    try {
        New-Item -Path $RegPath -Force | Out-Null
        New-ItemProperty -Path $RegPath -Name "Debugger" -PropertyType String -Value $DebuggerPath -Force | Out-Null
        Write-Host "✓ BLOCKED (EXE): $ExeName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "✗ Failed to block EXE: $ExeName - $_" -ForegroundColor Red
        return $false
    }
}

function Unblock-Executable {
    param([string]$ExeName)
    
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$ExeName"
    
    try {
        if (Test-Path $RegPath) {
            Remove-Item -Path $RegPath -Recurse -Force
            Write-Host "✓ UNBLOCKED (EXE): $ExeName" -ForegroundColor Green
        }
        else {
            Write-Host "No block found for: $ExeName" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "✗ Failed to unblock EXE: $ExeName - $_" -ForegroundColor Red
    }
}

function Block-MicrosoftStoreApp {
    param([string]$AppName)
    
    try {
        # Get all installed packages
        $packages = Get-AppxPackage | Where-Object { $_.Name -like "*$AppName*" -or $_.DisplayName -like "*$AppName*" }
        
        if ($packages.Count -eq 0) {
            Write-Host "No Microsoft Store app found matching: $AppName" -ForegroundColor Yellow
            return $false
        }
        
        foreach ($package in $packages) {
            # Method 1: Disable the package
            Disable-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
            
            # Method 2: Add to AppLocker deny list (if AppLocker is available)
            if (Get-Command Get-AppLockerPolicy -ErrorAction SilentlyContinue) {
                $rule = Get-AppLockerFileInformation -Package $package.PackageFullName
                New-AppLockerPolicy -RuleType Package -User Everyone -Rule $rule | 
                    Set-AppLockerPolicy -Merge -ErrorAction SilentlyContinue
            }
            
            # Method 3: Block via Windows Firewall
            $appxManifest = Join-Path $package.InstallLocation "AppxManifest.xml"
            if (Test-Path $appxManifest) {
                $exeFiles = Get-ChildItem -Path $package.InstallLocation -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue
                foreach ($exe in $exeFiles) {
                    $ruleName = "Blocked_StoreApp_$($exe.Name)"
                    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Program $exe.FullName -Action Block -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "✓ BLOCKED (Store App): $($package.Name)" -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Host "✗ Failed to block Store App: $AppName - $_" -ForegroundColor Red
        return $false
    }
}

function Block-Process {
    param([string]$ProcessName)
    
    try {
        # Kill any running processes
        Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
        
        # Create scheduled task to monitor and kill process
        $taskName = "BlockProcess_$ProcessName"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `"while(`$true){Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 1}`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
        
        # Start the task now
        Start-ScheduledTask -TaskName $taskName
        
        Write-Host "✓ BLOCKED (Process Monitor): $ProcessName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "✗ Failed to set process monitor: $ProcessName - $_" -ForegroundColor Red
        return $false
    }
}

function Block-AppViaPath {
    param([string]$AppName)
    
    # Search common paths for the app
    $searchPaths = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:LOCALAPPDATA\Programs",
        "$env:ProgramData",
        "$env:APPDATA",
        "$env:LOCALAPPDATA",
        "C:\Program Files\WindowsApps",
        "$env:WINDIR\System32",
        "$env:WINDIR\SysWOW64"
    )
    
    $foundPaths = @()
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $foundPaths += Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue | 
                          Where-Object { 
                              $_.Name -like "*$AppName*" -and 
                              ($_.Extension -in '.exe', '.com', '.bat', '.cmd', '.ps1', '.msi', '.appx')
                          } | 
                          Select-Object -First 5 -ExpandProperty FullName
        }
    }
    
    if ($foundPaths.Count -gt 0) {
        Write-Host "Found $($foundPaths.Count) file(s) for $AppName" -ForegroundColor Cyan
        foreach ($filePath in $foundPaths) {
            # Block via Firewall
            $ruleName = "Blocked_$([System.IO.Path]::GetFileName($filePath))"
            New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Program $filePath -Action Block -ErrorAction SilentlyContinue
            
            # Set file permissions to deny execute
            $acl = Get-Acl $filePath
            $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "ExecuteFile", "Deny")
            $acl.AddAccessRule($denyRule)
            Set-Acl -Path $filePath -AclObject $acl -ErrorAction SilentlyContinue
            
            Write-Host "  ✓ Blocked: $filePath" -ForegroundColor DarkGreen
        }
        return $true
    }
    
    return $false
}

# Main execution
Write-Host "=== Enhanced Application Blocker ===" -ForegroundColor Cyan
Write-Host "Targeting: $($AppNames -join ', ')" -ForegroundColor Yellow
Write-Host ""

foreach ($app in $AppNames) {
    Write-Host "`nProcessing: $app" -ForegroundColor Magenta
    
    # Normalize name
    $cleanName = $app -replace '\.exe$|\.com$|\.bat$|\.ps1$', ''
    $exeName = "$cleanName.exe"
    
    if ($Unblock) {
        # Unblock operations
        Unblock-Executable -ExeName $exeName
        
        # Remove firewall rules
        Get-NetFirewallRule -DisplayName "Blocked_*$cleanName*" -ErrorAction SilentlyContinue | 
            Remove-NetFirewallRule
        
        # Remove process monitors
        Get-ScheduledTask -TaskName "BlockProcess_$cleanName" -ErrorAction SilentlyContinue | 
            Unregister-ScheduledTask -Confirm:$false
        
        Write-Host "✓ Unblocked all methods for: $app" -ForegroundColor Green
    }
    else {
        $blocked = $false
        
        # Method 1: IFEO Registry (EXE blocking)
        if (Block-Executable -ExeName $exeName) {
            $blocked = $true
        }
        
        # Method 2: Microsoft Store Apps
        if (Block-MicrosoftStoreApp -AppName $cleanName) {
            $blocked = $true
        }
        
        # Method 3: Process Monitoring (to catch and kill)
        if (Block-Process -ProcessName $cleanName) {
            $blocked = $true
        }
        
        # Method 4: Path-based blocking
        if (Block-AppViaPath -AppName $cleanName) {
            $blocked = $true
        }
        
        if (-not $blocked) {
            Write-Host "⚠ WARNING: Could not find or block $app using automatic methods" -ForegroundColor Yellow
            Write-Host "  You may need to provide the full path manually or check if the app is installed." -ForegroundColor Gray
        }
    }
}

Write-Host "`n---- Completed Blocking Applications ----" -ForegroundColor Green

# Display summary of blocked apps
Write-Host "`n=== Blocking Summary ===" -ForegroundColor Cyan
$blockedExes = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\" -ErrorAction SilentlyContinue | 
               Where-Object { $_.PSChildName -like "*.exe" } | 
               Select-Object -ExpandProperty PSChildName

if ($blockedExes) {
    Write-Host "Blocked EXEs:" -ForegroundColor Yellow
    $blockedExes | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
}

# Show blocked firewall rules
$blockedFirewall = Get-NetFirewallRule | Where-Object { $_.DisplayName -like "Blocked_*" -and $_.Action -eq "Block" }
if ($blockedFirewall) {
    Write-Host "`nBlocked Firewall Rules:" -ForegroundColor Yellow
    $blockedFirewall | ForEach-Object { Write-Host "  • $($_.DisplayName)" -ForegroundColor Gray }
}
