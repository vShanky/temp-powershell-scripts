# powershell -ExecutionPolicy Bypass -File Delete-user-forcefully.ps1 -UserName "Shashank"

# This script delete the user forcefully, with all access, whatever he have.
param(
    [Parameter(Mandatory = $true)]
    [string]$UserName
)

# --------------------------
# Ensure script runs as admin
# --------------------------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "Restarting script as Administrator..."
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -UserName `"$UserName`"" -Verb RunAs
    exit
}

# --------------------------
# Main Script
# --------------------------

# Check if the user exists
if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {

    Write-Host "Trying to remove user $UserName..."

    # Remove from all local groups
    $groups = Get-LocalGroup
    foreach ($g in $groups) {
        try {
            Remove-LocalGroupMember -Group $g.Name -Member $UserName -ErrorAction SilentlyContinue
        } catch {}
    }

    # Optional: Delete the profile folder
    $profilePath = "C:\Users\$UserName"
    if (Test-Path $profilePath) {
        Write-Host "Removing user profile at $profilePath..."
        Remove-Item -Path $profilePath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove local user
    try {
        Remove-LocalUser -Name $UserName -ErrorAction Stop
        Write-Host "User $UserName removed successfully."
    }
    catch {
        Write-Host "Failed to remove user normally. Trying WMI method..."

        # Alternate force-removal via WMI
        Get-WmiObject Win32_UserAccount -Filter "Name='$UserName'" |
            Remove-WmiObject -ErrorAction SilentlyContinue

        Write-Host "User removal attempt completed using WMI."
    }

}
else {
    Write-Host "User $UserName does not exist."
}
