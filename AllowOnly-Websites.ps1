param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$AllowedDomains,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$TargetUser,

    [Parameter(Mandatory = $false, Position = 2)]
    [string]$Password = "Pass@123"   # default
)

Write-Host "`n=== Checking user ===" -ForegroundColor Cyan

$userExists = Get-LocalUser -Name $TargetUser -ErrorAction SilentlyContinue

if ($null -eq $userExists) {
    Write-Host "User '$TargetUser' does NOT exist. Creating user..." -ForegroundColor Yellow
    
    $securePass = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $TargetUser -Password $securePass

    Add-LocalGroupMember -Group "Users" -Member $TargetUser

    Write-Host "User created successfully." -ForegroundColor Green
} else {
    Write-Host "User '$TargetUser' already exists. Skipping create." -ForegroundColor Green
}

Write-Host "`n=== Applying allow-only rules===" -ForegroundColor Cyan

# remove old rules for user
Get-NetFirewallRule | Where-Object {
    $_.DisplayName -like "Allow_Web_${TargetUser}_*" -or
    $_.DisplayName -eq "Block_All_Other_Web_$TargetUser"
} | Remove-NetFirewallRule -ErrorAction SilentlyContinue

# resolve IPs
$AllowedIPs = @()

foreach ($domain in $AllowedDomains) {
    try {
        $ips = (Resolve-DnsName $domain -Type A | Select-Object -ExpandProperty IPAddress)
        $AllowedIPs += $ips
    } catch {}
}

$AllowedIPs = $AllowedIPs | Select-Object -Unique

foreach ($ip in $AllowedIPs) {
    New-NetFirewallRule -DisplayName "Allow_Web_${TargetUser}_$ip" -Direction Outbound -RemoteAddress $ip -Action Allow -Protocol TCP -LocalUser $TargetUser -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "Allow_Web_${TargetUser}_$ip" -Direction Outbound -RemoteAddress $ip -Action Allow -Protocol UDP -LocalUser $TargetUser -ErrorAction SilentlyContinue
}

New-NetFirewallRule -DisplayName "Block_All_Other_Web_$TargetUser" -Direction Outbound -Action Block -Protocol TCP -RemotePort 80,443 -LocalUser $TargetUser -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Block_All_Other_Web_$TargetUser" -Direction Outbound -Action Block -Protocol UDP -RemotePort 80,443 -LocalUser $TargetUser -ErrorAction SilentlyContinue

Write-Host "`nDONE!" -ForegroundColor Cyan
Write-Host "User: $TargetUser"
Write-Host "Allowed sites only: $($AllowedDomains -join ', ')"


# powershell -ExecutionPolicy Bypass -File AllowOnly-Websites.ps1 -AllowedDomains "google.com","wwe.com","stackoverflow.com" -TargetUser "KidUser"

# $user="KidUser"
# Get-NetFirewallRule | Where-Object {
#     $_.DisplayName -like "Allow_Web_${user}_*" -or
#     $_.DisplayName -eq "Block_All_Other_Web_$user"
# } | Remove-NetFirewallRule
