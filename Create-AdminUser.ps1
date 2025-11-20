# This will create an Admin user in windows, Run as Administrator

#powershell.exe -ExecutionPolicy Bypass -File Create-AdminUser.ps1 -AdminUser "adminuser" -AdminPassword "Adm!nPass123"

#Get-LocalUser  --  It shows the list of users

param(
    [Parameter(Mandatory=$true)]
    [string]$AdminUser,

    [Parameter(Mandatory=$true)]
    [string]$AdminPassword
)

# Convert password to secure string
$SecurePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force

# Create user account
New-LocalUser -Name $AdminUser -Password $SecurePassword -FullName $AdminUser -Description "Administrator local user account" -ErrorAction Stop

# Add user to Administrators group
Add-LocalGroupMember -Group "Administrators" -Member $AdminUser -ErrorAction Stop

Write-Host "Administrator user '$AdminUser' created successfully!" -ForegroundColor Green
