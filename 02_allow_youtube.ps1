# Removes youtube block entries from hosts
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
(Get-Content $hosts) | Where-Object {$_ -notmatch 'youtube\.com'} | Set-Content $hosts
ipconfig /flushdns
Write-Host "YouTube unblocked (hosts)."
