# This will create an user with admin priviledges in windows , Run as Administrator

# Variables (edit these)
$AdminUser = "adminuser"
$AdminPassword = "Adm!nPass123"

# Convert password to secure string
$SecurePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force

# Create user account
New-LocalUser -Name $AdminUser -Password $SecurePassword -FullName "Administrator User" -Description "Admin local user account"

# Add user to Administrators group
Add-LocalGroupMember -Group "Administrators" -Member $AdminUser

Write-Host "Administrator user '$AdminUser' created successfully!"
