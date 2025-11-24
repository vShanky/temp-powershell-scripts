#powershell -ExecutionPolicy Bypass -File .\AllowOnly-Websites.ps1 ` -AllowedDomains "google.com","wwe.com","stackoverflow.com"

# Script will :  Remove old rules, Add new ones based on domains you pass in command, Block everything else again

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$AllowedDomains
)

Write-Host "`n=== Allow-only mode for websites ===" -ForegroundColor Cyan
Write-Host "Allowed domains: $($AllowedDomains -join ', ')" -ForegroundColor Yellow

# 1) Clean old rules (so you can re-run with new domains)
Write-Host "`nRemoving old rules (if any)..." -ForegroundColor DarkYellow
Get-NetFirewallRule | Where-Object {
    $_.DisplayName -like "Allow_Web_*" -or
    $_.DisplayName -eq "Block_All_Other_Web"
} | Remove-NetFirewallRule -ErrorAction SilentlyContinue

# 2) Resolve domains -> IPs
$AllowedIPs = @()

Write-Host "`nResolving domains to IPs..." -ForegroundColor Yellow
foreach ($domain in $AllowedDomains) {
    try {
        $ips = (Resolve-DnsName $domain -Type A | Select-Object -ExpandProperty IPAddress)
        if ($ips) {
            $AllowedIPs += $ips
            Write-Host "  $domain -> $($ips -join ', ')"
        } else {
            Write-Host "  $domain -> no IPs found" -ForegroundColor Red
        }
    } catch {
        Write-Host "  Failed to resolve $domain" -ForegroundColor Red
    }
}

$AllowedIPs = $AllowedIPs | Select-Object -Unique

if (-not $AllowedIPs) {
    Write-Host "`nNo IPs resolved. Aborting." -ForegroundColor Red
    exit
}

# 3) Create ALLOW rules per IP
Write-Host "`nCreating ALLOW rules..." -ForegroundColor Green
foreach ($ip in $AllowedIPs) {
    $ruleName = "Allow_Web_$ip"
    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -RemoteAddress $ip -Action Allow -Protocol TCP -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -RemoteAddress $ip -Action Allow -Protocol UDP -ErrorAction SilentlyContinue
}

# 4) Block everything else on ports 80/443
Write-Host "`nCreating BLOCK rule for all other web traffic..." -ForegroundColor Red
New-NetFirewallRule -DisplayName "Block_All_Other_Web" -Direction Outbound -Action Block -Protocol TCP -RemotePort 80,443 -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Block_All_Other_Web" -Direction Outbound -Action Block -Protocol UDP -RemotePort 80,443 -ErrorAction SilentlyContinue

Write-Host "`nDONE ✅"
Write-Host "Only these domains should work now: $($AllowedDomains -join ', ')" -ForegroundColor Cyan
Write-Host "To revert, remove rules with name Allow_Web_* and Block_All_Other_Web."
