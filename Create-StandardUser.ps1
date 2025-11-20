# This will create an standard normal user in Windows, run as administrator only

# Variables (edit these)
$UserName = "ashar"
$Password = "Pass@123"

# Convert password to secure string
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# Create user account
New-LocalUser -Name $UserName -Password $SecurePassword -FullName "Standard User" -Description "Normal local user account"

# Add user to 'Users' group only
Add-LocalGroupMember -Group "Users" -Member $UserName

Write-Host "Standard user '$UserName' created successfully!"
