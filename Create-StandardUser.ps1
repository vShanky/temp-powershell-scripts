# This is script to create an standard user , Run as Administrator 
# powershell.exe -ExecutionPolicy Bypass -File Create-StandardUser.ps1 -UserName "ashar" -Password "Pass@123"

# Get-LocalUser  --  Shows the list of users


param(
    [Parameter(Mandatory=$true)]
    [string]$UserName,

    [Parameter(Mandatory=$true)]
    [string]$Password
)

# Convert password to secure string
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# Create user account
New-LocalUser -Name $UserName -Password $SecurePassword -FullName $UserName -Description "Standard local user account" -ErrorAction Stop

# Add user to Users group
Add-LocalGroupMember -Group "Users" -Member $UserName -ErrorAction Stop

Write-Host "Standard user '$UserName' created successfully!" -ForegroundColor Green
